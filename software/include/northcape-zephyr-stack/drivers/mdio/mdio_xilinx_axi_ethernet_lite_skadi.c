/*
 * Xilinx AXI Ethernet Lite MDIO
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(eth_xilinx_axi_ethernet_lite_mdio, CONFIG_ETHERNET_LOG_LEVEL);

#define DT_DRV_COMPAT xlnx_xps_ethernetlite_3_00_a_mdio

#include <zephyr/kernel.h>
#include <zephyr/drivers/mdio.h>

#include <stdint.h>

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_device.h>

#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/skadi_mutex.h>

#define MDIO_XILINX_AXI_ETHERNET_LITE_MAX_PHY_DEVICES 32

#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_OFFSET 		0x07e4
#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_WRITE_DATA_REG_OFFSET 	0x07e8
#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_READ_DATA_REG_OFFSET 	0x07ec
#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_OFFSET 		0x07f0

#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_MDIO_ENABLE_MASK 	BIT(3)
#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_MDIO_BUSY_MASK 		BIT(0)
#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_MDIO_DISABLE_MASK 	0

#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_OP_READ				BIT(10)
#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_OP_WRITE				0
#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_SHIFT_REGADDR 		0
#define MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_SHIFT_PHYADDR 		5

struct mdio_xilinx_axi_ethernet_lite_data {
	struct k_mutex mutex;
	bool bus_enabled;
};

struct mdio_xilinx_axi_ethernet_lite_config {
	void *reg;
};

SKADI_DECLARE_DEVICE_REPRESENTATION_WRAPPER;


static inline uint32_t mdio_xilinx_axi_ethernet_lite_read_reg(const struct mdio_xilinx_axi_ethernet_lite_config *config, mem_addr_t reg){
	return sys_read32((mem_addr_t)config->reg + reg);
}

static inline void mdio_xilinx_axi_ethernet_lite_write_reg(const struct mdio_xilinx_axi_ethernet_lite_config *config, mem_addr_t reg, uint32_t value){
	sys_write32(value, (mem_addr_t)config->reg + reg);
}

static inline int mdio_xilinx_axi_ethernet_lite_check_busy(const struct mdio_xilinx_axi_ethernet_lite_config *config){
	uint32_t mdio_control_reg_val = mdio_xilinx_axi_ethernet_lite_read_reg(config, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_OFFSET);

	return mdio_control_reg_val & MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_MDIO_BUSY_MASK ? -EBUSY : 0;
}

static inline void mdio_xilinx_axi_ethernet_lite_set_addr(const struct mdio_xilinx_axi_ethernet_lite_config *config, uint8_t prtad, uint8_t regad, bool is_read){
	uint32_t mdio_addr_val = is_read ? MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_OP_READ : MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_OP_WRITE;
	
	/* range check done below in read/write functions */
	mdio_addr_val |= (uint32_t)regad << MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_SHIFT_REGADDR;
	mdio_addr_val |= (uint32_t)prtad << MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_SHIFT_PHYADDR;

	mdio_xilinx_axi_ethernet_lite_write_reg(config, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_ADDRESS_REG_OFFSET, mdio_addr_val);
}

static inline void bus_enable(const struct device *dev){
	const struct mdio_xilinx_axi_ethernet_lite_config *config = dev->config;
	struct mdio_xilinx_axi_ethernet_lite_data *data = dev->data;

	(void)skadi_mutex_lock(&data->mutex, K_FOREVER);

	mdio_xilinx_axi_ethernet_lite_write_reg(config, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_OFFSET, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_MDIO_ENABLE_MASK);

	data->bus_enabled = true;

	(void)skadi_mutex_unlock(&data->mutex);
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, mdio_xilinx_axi_ethernet_lite_bus_enable, const struct device *orig_dev)
{
	bus_enable(skadi_get_own_device_representation(orig_dev));
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(mdio_xilinx_axi_ethernet_lite_bus_enable)

#define MDIO_MAX_WAIT_US 1000

static inline int xilinx_axi_ethernet_lite_mdio_complete_transaction(const struct mdio_xilinx_axi_ethernet_lite_config *config){
	int waited_cycles = 0;
	/* start transaction - everything set up */
	mdio_xilinx_axi_ethernet_lite_write_reg(config, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_OFFSET, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_MDIO_ENABLE_MASK | MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_MDIO_BUSY_MASK);

	while(mdio_xilinx_axi_ethernet_lite_check_busy(config) && waited_cycles < MDIO_MAX_WAIT_US){
		skadi_yield();
		/* no need to block the CPU */
		k_busy_wait(1);
		waited_cycles ++;
	}

	if(waited_cycles == MDIO_MAX_WAIT_US){
		LOG_ERR("Timed out waiting for MDIO transaction to complete!");
		return -ETIMEDOUT;
	}
	/* busy went low - transaction complete */
	return 0;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, mdio_xilinx_axi_ethernet_lite_read, const struct device *orig_dev, uint8_t prtad, uint8_t regad, uint16_t *value)
{
	const struct device *dev = skadi_get_own_device_representation(orig_dev);
	const struct mdio_xilinx_axi_ethernet_lite_config *config = dev->config;
	struct mdio_xilinx_axi_ethernet_lite_data *data = dev->data;
	
	if(prtad >= MDIO_XILINX_AXI_ETHERNET_LITE_MAX_PHY_DEVICES){
		LOG_ERR("Requested read port address %"PRIu8" not supported - max %d", prtad, MDIO_XILINX_AXI_ETHERNET_LITE_MAX_PHY_DEVICES);
		return -ENOSYS;
	}
	
	(void)skadi_mutex_lock(&data->mutex, K_FOREVER);

	if(!data->bus_enabled){
		LOG_ERR("MDIO bus not enabled!");
		(void)skadi_mutex_unlock(&data->mutex);
		return -ENOSYS;
	}
	if(mdio_xilinx_axi_ethernet_lite_check_busy(config)){
		LOG_ERR("MDIO bus busy!");
		(void)skadi_mutex_unlock(&data->mutex);
		return -ENOSYS;
	}

	mdio_xilinx_axi_ethernet_lite_set_addr(config, prtad, regad, true);

	if(xilinx_axi_ethernet_lite_mdio_complete_transaction(config)){
		(void)skadi_mutex_unlock(&data->mutex);
		return -EIO;
	}

	*value = (uint16_t) mdio_xilinx_axi_ethernet_lite_read_reg(config, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_READ_DATA_REG_OFFSET);

	(void)skadi_mutex_unlock(&data->mutex);

	return 0;

}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(mdio_xilinx_axi_ethernet_lite_read)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, mdio_xilinx_axi_ethernet_lite_write, const struct device *orig_dev, uint8_t prtad, uint8_t regad, uint16_t value)
{
	const struct device *dev = skadi_get_own_device_representation(orig_dev);
	const struct mdio_xilinx_axi_ethernet_lite_config *config = dev->config;
	struct mdio_xilinx_axi_ethernet_lite_data *data = dev->data;

	if(prtad >= MDIO_XILINX_AXI_ETHERNET_LITE_MAX_PHY_DEVICES){
		LOG_ERR("Requested write port address %"PRIu8" not supported - max %d", prtad, MDIO_XILINX_AXI_ETHERNET_LITE_MAX_PHY_DEVICES);
		return -ENOSYS;
	}
	(void)skadi_mutex_lock(&data->mutex, K_FOREVER);
	if(!data->bus_enabled){
		LOG_ERR("MDIO bus not enabled!");
		(void)skadi_mutex_unlock(&data->mutex);
		return -ENOSYS;
	}
	if(mdio_xilinx_axi_ethernet_lite_check_busy(config)){
		LOG_ERR("MDIO bus busy!");
		(void)skadi_mutex_unlock(&data->mutex);
		return -ENOSYS;
	}
	mdio_xilinx_axi_ethernet_lite_set_addr(config, prtad, regad, false);
	mdio_xilinx_axi_ethernet_lite_write_reg(config, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_WRITE_DATA_REG_OFFSET, value);

	if(xilinx_axi_ethernet_lite_mdio_complete_transaction(config)){
		(void)skadi_mutex_unlock(&data->mutex);
		return -EIO;
	}

	(void)skadi_mutex_unlock(&data->mutex);

	return 0;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(mdio_xilinx_axi_ethernet_lite_write)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, mdio_xilinx_axi_ethernet_lite_bus_disable, const struct device *orig_dev)
{
	const struct device *dev = skadi_get_own_device_representation(orig_dev);
	const struct mdio_xilinx_axi_ethernet_lite_config *config = dev->config;
	struct mdio_xilinx_axi_ethernet_lite_data *data = dev->data;


	(void)skadi_mutex_lock(&data->mutex, K_FOREVER);
	mdio_xilinx_axi_ethernet_lite_write_reg(config, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_OFFSET, MDIO_XILINX_AXI_ETHERNET_LITE_MDIO_CONTROL_REG_MDIO_DISABLE_MASK);

	data->bus_enabled = false;

	(void)skadi_mutex_unlock(&data->mutex);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(mdio_xilinx_axi_ethernet_lite_bus_disable)

static struct mdio_driver_api mdio_xilinx_axi_ethernet_lite_api = {
	0
};

static bool mdio_xilinx_axienet_skadi_init(void){
	SKADI_INSTALL_TIME_INTERRUPT_HOOK;

	/* We need to call this in a separate initialization function, while the device is still writable. */

	LOG_INF("Preparing API!");
	mdio_xilinx_axi_ethernet_lite_api.bus_disable = SKADI_SUBSYSTEM_FUNCTION_POINTER(mdio_xilinx_axi_ethernet_lite_bus_disable);
	mdio_xilinx_axi_ethernet_lite_api.bus_enable = SKADI_SUBSYSTEM_FUNCTION_POINTER(mdio_xilinx_axi_ethernet_lite_bus_enable);
	mdio_xilinx_axi_ethernet_lite_api.read = SKADI_SUBSYSTEM_FUNCTION_POINTER(mdio_xilinx_axi_ethernet_lite_read);
	mdio_xilinx_axi_ethernet_lite_api.write = SKADI_SUBSYSTEM_FUNCTION_POINTER(mdio_xilinx_axi_ethernet_lite_write);

	SKADI_DEVICES_API_INIT(mdio_xilinx_axi_ethernet_lite_api)

	LOG_INF("API initialized!");
	return true;
}
SKADI_SUBSYSTEM_INIT_FUNCTIONS(mdio_xilinx_axienet_skadi_init);

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, mdio_xilinx_axi_ethernet_lite_probe, const struct device *orig_dev)
{
	const struct device *dev = skadi_get_own_device_representation(orig_dev);
	struct mdio_xilinx_axi_ethernet_lite_data *data = dev->data;

	(void)skadi_mutex_init(&data->mutex);

	bus_enable(dev);

	return 0;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(mdio_xilinx_axi_ethernet_lite_probe)



#define XILINX_AXI_ETHERNET_LITE_MDIO_INIT(inst)					\
																	\
	static const struct mdio_xilinx_axi_ethernet_lite_config        \
	mdio_xilinx_axi_ethernet_lite_config##inst = {					\
	.reg = (void *)(uintptr_t)DT_REG_ADDR(DT_INST_PARENT(inst)),	\
	};                                                      		\
	static struct mdio_xilinx_axi_ethernet_lite_data                \
	mdio_xilinx_axi_ethernet_lite_data##inst = {					\
	0																\
	};                                                      		\
	DEVICE_DT_INST_DEFINE(inst, NULL,								\
		  NULL,														\
		  &mdio_xilinx_axi_ethernet_lite_data##inst,				\
		  &mdio_xilinx_axi_ethernet_lite_config##inst,				\
		  POST_KERNEL,												\
		  CONFIG_MDIO_INIT_PRIORITY,								\
		  NULL);

#define DT_DRV_COMPAT xlnx_xps_ethernetlite_3_00_a_mdio
DT_INST_FOREACH_STATUS_OKAY(XILINX_AXI_ETHERNET_LITE_MDIO_INIT)

SKADI_GENERATE_DEVICE_REPRESENTATION_WRAPPER;
