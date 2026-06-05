#include <cv64a6.h>
#include <zephyr/arch/riscv/csr.h>
#include <zephyr/device.h>
#include <zephyr/skadi/skadi_ops_driver.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(pulp_riscv_debug_module, CONFIG_SKADI_LOG_LEVEL);

struct pulp_riscv_debug_module_config {
    void *reg;
    uint32_t reg_size;
};

struct pulp_riscv_debug_module_data {
    void *capability;
};

static int pulp_riscv_debug_module_init(const struct device *dev){
    const struct pulp_riscv_debug_module_config *config = dev->config;
    struct pulp_riscv_debug_module_data *data = dev->data;

    __ASSERT_NO_MSG(config);
    __ASSERT_NO_MSG(data);

    if(!config || !data){
        return -EINVAL;
    }

    if(!skadi_cap_ops_derive_simple(config->reg, config->reg_size, skadi_get_capability_offset(config->reg), &data->capability) || !data->capability){
        LOG_ERR("Could not derive capability for debug module!");
        return -EINVAL;
    }

    LOG_INF("Derived capability %p for debug module with MMIO address space from %p-%p", (void*)data->capability, config->reg, (void*) ((uintptr_t)config->reg + (uintptr_t)config->reg_size));

    csr_write(CV64A6_CSR_DEBUG_OFFSET, (uintptr_t)data->capability);

    return 0;
    
}

#define PULP_RISCV_DBG_MODULE_INIT(inst)                                                                  \
	static const struct pulp_riscv_debug_module_config pulp_riscv_debug_module##inst##_config = {        \
		.reg = (void *)DT_INST_REG_ADDR(inst),                                  \
		.reg_size = DT_INST_REG_SIZE(inst)                                                  \
	};                                                                                         \
	static struct pulp_riscv_debug_module_data pulp_riscv_debug_module##inst##_data = {                  \
		0   \
	};                                                                                         \
                                                                                                   \
	DEVICE_DT_INST_DEFINE(inst, pulp_riscv_debug_module_init, NULL,                                \
			      &pulp_riscv_debug_module##inst##_data,                                    \
			      &pulp_riscv_debug_module##inst##_config, PRE_KERNEL_1,                     \
			      CONFIG_SKADI_DEBUG_MODULE_INIT_PRIO, NULL);

#define DT_DRV_COMPAT pulp_riscv_dbg_0_8_1
DT_INST_FOREACH_STATUS_OKAY(PULP_RISCV_DBG_MODULE_INIT)

