
#include <sys/types.h>
#include <zephyr/kernel.h>
#include <zephyr/net/ethernet.h>
#include <ethernet/eth_stats.h>
#include <zephyr/drivers/dma.h>

#include <zephyr/net/phy.h>
#include <zephyr/irq.h>
#include <zephyr/sys/barrier.h>

#include "../dma/dma_xilinx_axi_dma.h"

#ifdef CONFIG_SKADI_OS

#include <zephyr/skadi/skadi_ops_driver.h>

#include <zephyr/arch/cache.h>

#if defined(CONFIG_NET_L2_PTP)
#include <zephyr/net/gptp.h>
#include <zephyr/skadi/skadi_sem.h>
#include <zephyr/skadi/subsystems/ptp/skadi_ptp_clock.h>
#include <zephyr/skadi/subsystems/ptp/skadi_ptp_clock_ha1588.h>
#endif /* CONFIG_PTP || CONFIG_NET_GPTP */

#endif

#define LOG_MODULE_NAME eth_xilinx_axienet
#define LOG_LEVEL       CONFIG_ETHERNET_LOG_LEVEL
#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(LOG_MODULE_NAME);

#ifdef CONFIG_SKADI_OS

#include <zephyr/llext/llext.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_irq.h>
#include <zephyr/skadi/skadi_device.h>
#include <zephyr/skadi/skadi_timer.h>

#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/subsystems/net/skadi_ethernet_subsystem.h>
#include <zephyr/skadi/subsystems/net/skadi_dma.h>
#include <zephyr/skadi/subsystems/net/skadi_phy.h>
#include <zephyr/skadi/subsystems/net/skadi_net.h>

#define dma_start(...) skadi_dma_start(__VA_ARGS__)
#define dma_stop(...) skadi_dma_stop(__VA_ARGS__)
#define dma_config(...) skadi_dma_config(__VA_ARGS__)
#define dma_reload(...) skadi_dma_reload(__VA_ARGS__)

#endif


/* register offsets and masks */
#define XILINX_AXIENET_INTERRUPT_STATUS_OFFSET         0x0000000C
#define XILINX_AXIENET_INTERRUPT_STATUS_RXREJ_MASK     0x00000008
#define XILINX_AXIENET_INTERRUPT_STATUS_RXFIFOOVR_MASK 0x00000010 /* Rx fifo overrun */
#define XILINX_AXIENET_INTERRUPT_PENDING_OFFSET        0x00000010

#define XILINX_AXIENET_INTERRUPT_PENDING_RXCMPIT_MASK     0x00000004 /* Rx complete */
#define XILINX_AXIENET_INTERRUPT_PENDING_RXRJECT_MASK     0x00000008 /* Rx frame rejected */
#define XILINX_AXIENET_INTERRUPT_PENDING_RXFIFOOVR_MASK   0x00000010 /* Rx fifo overrun */
#define XILINX_AXIENET_INTERRUPT_PENDING_TXCMPIT_MASK     0x00000020 /* Tx complete */
#define XILINX_AXIENET_INTERRUPT_PENDING_RXDCMLOCK_MASK   0x00000040 /* Rx Dcm Lock */
#define XILINX_AXIENET_INTERRUPT_PENDING_MGTRDY_MASK      0x00000080 /* MGT clock Lock */
#define XILINX_AXIENET_INTERRUPT_PENDING_PHYRSTCMPLT_MASK 0x00000100 /* Phy Reset complete */

#define XILINX_AXIENET_INTERRUPT_PENDING_RXREJ_MASK 0x00000008
#define XILINX_AXIENET_INTERRUPT_ENABLE_OFFSET      0x00000014
#define XILINX_AXIENET_INTERRUPT_ENABLE_RXREJ_MASK  0x00000008
#define XILINX_AXIENET_INTERRUPT_ENABLE_OVR_MASK    0x00000010 /* FIFO overrun */

#define XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_0_REG_OFFSET     0x00000400
#define XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET     0x00000404
#define XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_RX_EN_MASK 0x10000000
#define XILINX_AXIENET_RECEIVER_CONFIGURATION_FLOW_CONTROL_OFFSET   0x0000040C
#define XILINX_AXIENET_RECEIVER_CONFIGURATION_FLOW_CONTROL_EN_MASK  0x20000000
#define XILINX_AXIENET_TX_CONTROL_REG_OFFSET                        0x00000408
#define XILINX_AXIENET_TX_CONTROL_TX_EN_MASK                        (1 << 11)

#define XILINX_AXIENET_UNICAST_ADDRESS_WORD_0_OFFSET 0x00000700
#define XILINX_AXIENET_UNICAST_ADDRESS_WORD_1_OFFSET 0x00000704

#define ETH_ALEN 6

/* otherwise, buffers will be smaller... - also includes 4 bytes for final length */
#define XILINX_AXIENET_ETH_BUFFER_SIZE NET_ETH_MAX_FRAME_SIZE
		
/* device state */
struct xilinx_axienet_data {
	struct k_timer timer;

	struct net_pkt *tx_buffer[CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_TX];
	struct net_pkt *rx_buffer[CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX];

	size_t rx_populated_buffer_index, rx_completed_buffer_index;
	size_t tx_populated_buffer_index, tx_completed_buffer_index;

	struct net_if *interface;

#if defined(CONFIG_NET_L2_PTP)
	/* index of a data buffer whose net_pkt is currently waiting for a tx timestamp, or -1 if none*/
	ssize_t tx_timestamp_buf_index;
	struct net_ptp_time tx_timestamp;
	struct k_sem tx_tstamp_available;
	int tx_timestamp_status;
#ifdef CONFIG_PTP_CLOCK_HA1588
	/* 
	 * metadata for the packet that is to be sent
	 * crucial to verify that we have the correct timestamp
	 */
	uint16_t tx_timestamp_ptp_seqid;
	uint8_t tx_timestamp_ptp_msgid;

	bool ha1588_was_reset;
#endif /* CONFIG_PTP_CLOCK_HA1588 */
#endif /* CONFIG_PTP || CONFIG_NET_GPTP */

	/* used to re-start RX from TX callbacks, for cases in which no RX buffer was available */
	int failed_rx_setups;

	/* device mac address */
	uint8_t mac_addr[NET_ETH_ADDR_LEN];

	bool dma_is_configured_rx;
};

/* global configuration per Ethernet device */
struct xilinx_axienet_config {
	void (*config_func)(const struct xilinx_axienet_data *dev);
	const struct device *dma;

	const struct device *phy;

#if defined(CONFIG_NET_L2_PTP)
	const struct device *ptp_clock;
#endif

	void *reg;

	bool have_irq, have_rx_csum_offload, have_tx_csum_offload;
#if defined(CONFIG_NET_L2_PTP)
	bool have_ha1588_tsu;
#endif
};

/* TX packet in flight with / to DMA */
struct xilinx_axienet_tx_packet_in_flight {
	struct dma_block_config fragments[CONFIG_ETH_XILINX_AXIENET_FRAGMENTS_MAX];
};

const static struct device *skadi_get_own_device_representation(const struct device *dev);

static struct phy_link_state *link_state;

static struct dma_block_config *rx_buffer_cap[CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX];

static struct xilinx_axienet_tx_packet_in_flight tx_packets_in_flight[CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_TX];

/* the Xilinx IP does not appreciate being narrow-written... */
__asm__(
    "skadi_axienet_store_atomically:\n\r"
    "sw a1, 0(a0)\n\r"
    "ret\n"
);

__asm__(
    "skadi_axienet_load_atomically:\n\r"
    "lw a0, 0(a0)\n\r"
    "ret\n"
);

#if defined(CONFIG_NET_L2_PTP)
static bool xilinx_axienet_check_ptp(struct net_pkt *pkt){
	
	if(ntohs(NET_ETH_HDR(pkt)->type) == NET_ETH_PTYPE_PTP){
		return true;
	}

	if(pkt->ptp_pkt || pkt->tx_timestamping){
		return true;
	}

	return false;
}
#endif

extern void skadi_axienet_store_atomically(volatile uint32_t *addr, uint32_t value);
extern uint32_t skadi_axienet_load_atomically(const volatile uint32_t *addr);


static void xilinx_axienet_write_register(const struct xilinx_axienet_config *config,
					  uintptr_t reg_offset, uint32_t value)
{
	volatile uint32_t *reg_addr = (uint32_t *)((uint8_t *)(config->reg) + reg_offset);
	
	skadi_axienet_store_atomically(reg_addr, value);
	
	barrier_dmem_fence_full(); /* make sure that write commits */
}

static uint32_t xilinx_axienet_read_register(const struct xilinx_axienet_config *config,
					     uintptr_t reg_offset)
{
	const volatile uint32_t *reg_addr = (uint32_t *)((uint8_t *)(config->reg) + reg_offset);
	const uint32_t ret = skadi_axienet_load_atomically(reg_addr);

	barrier_dmem_fence_full(); /* make sure that read commits */
	return ret;
}

static int setup_dma_rx_transfer(const struct device *dev,
				 const struct xilinx_axienet_config *config,
				 struct xilinx_axienet_data *data);

/* called by DMA when a packet is available */
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, xilinx_axienet_rx_callback, const struct device *dma, void *user_data, uint32_t channel,
				       int processed_packets)
{
	struct device *ethdev = (struct device *)user_data;
	struct xilinx_axienet_data *data = ethdev->data;
	const uint32_t *last_rx_sizes = (const uint32_t*)dma;
	int err;
	ARG_UNUSED(dma);

	__ASSERT_NO_MSG(data->interface);

	if (processed_packets < 0) {
		LOG_ERR("DMA RX error: %d", processed_packets);
	} else {
		for(int i = 0; i < processed_packets; i++){
			size_t next_descriptor =
				(data->rx_completed_buffer_index + 1) % CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX;
			size_t current_descriptor = data->rx_completed_buffer_index;
			struct net_pkt *pkt = data->rx_buffer[current_descriptor];
			/* we abuse the API here a bit... */
			unsigned int packet_size = last_rx_sizes[i];
			bool restricted;
			skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

			data->rx_completed_buffer_index = next_descriptor;

			if(!skadi_cap_ops_drop(rx_buffer_cap[current_descriptor])){
				LOG_WRN("Could not free RX buffer capability %p!", rx_buffer_cap[current_descriptor]);
			}
			else{
				LOG_DBG("Freed RX buffer capability %p!", rx_buffer_cap[current_descriptor]);
			}


			rx_buffer_cap[current_descriptor] = NULL;
			data->rx_buffer[current_descriptor] = NULL;

			__ASSERT_NO_MSG(current_descriptor < CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX);
			__ASSERT_NO_MSG(pkt);

			pkt->buffer->len = packet_size;

			(void)arch_dcache_invd_range(skadi_net_pkt_raw_buf(pkt), packet_size);

			restricted = skadi_cap_ops_restrict(skadi_net_pkt_raw_buf(pkt), restriction, XILINX_AXIENET_ETH_BUFFER_SIZE - packet_size, 0, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS);

			__ASSERT_NO_MSG(restricted);


#if defined(CONFIG_NET_L2_PTP)
			/* invalid by default */
			pkt->timestamp.nanosecond = UINT32_MAX;
			pkt->timestamp.second = UINT64_MAX;

			if(skadi_ptp_tsu_ha1588_packet_matches_rx_filter(pkt) || IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_RX)){
				const struct xilinx_axienet_config *config = ethdev->config;
				int ret;
#ifdef CONFIG_PTP_CLOCK_HA1588
				if(config->have_ha1588_tsu && data->ha1588_was_reset){
					/* can use precise timestamp from ha1588 */
					struct ha1588_tsu_timestamp rx_timestamp;

					ret = skadi_ptp_tsu_ha1588_get_rx_tstamp(config->ptp_clock, &rx_timestamp);

					memcpy(&pkt->timestamp, &rx_timestamp, sizeof(pkt->timestamp));

					LOG_DBG("Got RX timestamp %"PRIu64".%"PRIu32, pkt->timestamp.second, pkt->timestamp.nanosecond);
				}
				else{
#endif /* CONFIG_PTP_CLOCK_HA1588 */
					/* must use software timestamp */
					ret = skadi_ptp_clock_get(config->ptp_clock, &pkt->timestamp);
#ifdef CONFIG_PTP_CLOCK_HA1588
   				}
#endif /* CONFIG_PTP_CLOCK_HA1588 */

				if(data->ha1588_was_reset && ret){
					LOG_ERR("Failed to get RX timestamp!");
				}
			}
#endif

			LOG_DBG("Wrote data to packet - receiving with iface %p pkt %p!", data->interface, pkt);
			err = skadi_net_recv_data(data->interface, pkt);
			if (err < 0) {
				LOG_ERR("Could not receive packet data: %d", err);
				skadi_net_pkt_unref(pkt);
			} else {
				LOG_DBG("Packet with %u bytes received!\n", packet_size);
			}

			if (setup_dma_rx_transfer(ethdev, ethdev->config, ethdev->data)) {
				LOG_WRN("Could not set up next RX DMA transfer!");
				data->failed_rx_setups++;
				skadi_timer_start(&data->timer, K_MSEC(1), K_SECONDS(5));
			}

			LOG_DBG("DMA start rx done!");
		}
		
	}
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axienet_rx_callback)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, xilinx_axienet_tx_callback, const struct device *dev, void *user_data, uint32_t channel,
				       int processed_packets)
{
	struct device *ethdev = (struct device *)user_data;
	struct xilinx_axienet_data *data = ethdev->data;
	for(int i = 0; i < processed_packets && processed_packets >= 0; i++){
		size_t next_descriptor =
			(data->tx_completed_buffer_index + 1) % CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_TX;
		size_t current_descriptor = data->tx_completed_buffer_index;
		struct net_pkt *pkt = data->tx_buffer[current_descriptor];
		struct dma_block_config *block_config = &tx_packets_in_flight[current_descriptor].fragments[0];

		data->tx_completed_buffer_index = next_descriptor;

		for(int j = 0; j < CONFIG_ETH_XILINX_AXIENET_FRAGMENTS_MAX; j++){
			
			if(tx_packets_in_flight[current_descriptor].fragments[j].source_address){
				bool free_ok;
				block_config = block_config->next_block;

				free_ok = skadi_cap_ops_drop((void*)tx_packets_in_flight[current_descriptor].fragments[j].source_address);
				__ASSERT_NO_MSG(free_ok);	
			}
			else{
				/* monotonic numbering */
				break;
			}
		}


#if defined(CONFIG_NET_L2_PTP)
		if(current_descriptor == data->tx_timestamp_buf_index){
		   int ret;
		   const struct xilinx_axienet_config *config = ethdev->config;
	   		/* this packet needs a tx time */
#ifdef CONFIG_PTP_CLOCK_HA1588
   			if(config->have_ha1588_tsu){
				/* can use precise timestamp from ha1588 */
				struct ha1588_tsu_timestamp tx_timestamp;
				ret = skadi_ptp_tsu_ha1588_get_tx_tstamp(config->ptp_clock, &tx_timestamp);
				memcpy(&data->tx_timestamp, &tx_timestamp.tm, sizeof(data->tx_timestamp));
   			}
   			else{
#endif /* CONFIG_PTP_CLOCK_HA1588 */
   				/* must use software timestamp */
   				ret = skadi_ptp_clock_get(config->ptp_clock, &data->tx_timestamp);
#ifdef CONFIG_PTP_CLOCK_HA1588
   		}
#endif /* CONFIG_PTP_CLOCK_HA1588 */
   		data->tx_timestamp_status = ret;
   		skadi_sem_give(&data->tx_tstamp_available);
}
#endif

		/* can release packet - TX complete */
		skadi_net_pkt_unref(pkt);

		LOG_DBG("TX complete callback with descriptor %zu!", current_descriptor);
	}

	if (processed_packets < 0) {
		LOG_ERR("DMA TX error: %d", processed_packets);
	}
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axienet_tx_callback)

static int setup_dma_rx_transfer(const struct device *dev,
				 const struct xilinx_axienet_config *config,
				 struct xilinx_axienet_data *data)
{
	int err;
	size_t next_descriptor =
		(data->rx_populated_buffer_index + 1) % CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX;
	size_t current_descriptor = data->rx_populated_buffer_index;
	struct net_pkt *pkt;
	void* pkt_buffer_cap;
	struct dma_config dma_conf = {0}, *dma_conf_cap;
	void *cap_pointer;
	skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

	pkt = skadi_net_pkt_rx_alloc_with_buffer(data->interface, XILINX_AXIENET_ETH_BUFFER_SIZE,
		AF_UNSPEC, 0, K_NO_WAIT);
	
	if(!pkt){
		LOG_ERR("Could not allocate RX packet!");
		return -ENOMEM;
	}

	if (next_descriptor == data->rx_completed_buffer_index) {
		LOG_ERR("Cannot start RX via DMA - populated buffer %zu will run into completed"
			" buffer %zu!",
			data->rx_populated_buffer_index, data->rx_completed_buffer_index);
		skadi_net_pkt_unref(pkt);
		return -ENOSPC;
	}

	
	pkt_buffer_cap = skadi_cap_ops_derive_arg_wo(skadi_net_pkt_raw_buf(pkt), XILINX_AXIENET_ETH_BUFFER_SIZE);

	__ASSERT_NO_MSG(pkt_buffer_cap);

	if(!pkt_buffer_cap){
		LOG_WRN("Could not derive buffer cap!");
		return -ENOMEM;
	}

	/* for de-allocation of the capability */
	rx_buffer_cap[current_descriptor] = pkt_buffer_cap;
	data->rx_buffer[current_descriptor] = pkt;

	if (!data->dma_is_configured_rx) {
		struct dma_block_config head_block = {0}, *head_block_cap;

		/* these data structures are given to the DMA, so we need to use derive() to make them accessible */
		if(skadi_cap_ops_derive(&dma_conf, restriction, sizeof(dma_conf), skadi_get_capability_offset(&dma_conf), SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &cap_pointer) == false || cap_pointer == 0){
			LOG_ERR("Could not derive token for DMA config struct!");
			return -ENOMEM;
		}
		dma_conf_cap = (struct dma_config *) cap_pointer;

		if(skadi_cap_ops_derive(&head_block, restriction, sizeof(head_block), skadi_get_capability_offset(&head_block), SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &cap_pointer) == false || cap_pointer == 0){
			LOG_ERR("Could not derive token for DMA head block!");
			return -ENOMEM;
		}
		head_block_cap = (struct dma_block_config *) cap_pointer;	

		__ASSERT(head_block_cap != NULL, "Head block capability should have been set!");
		__ASSERT(dma_conf_cap != NULL, "DMA config capability should have been set!");

		head_block.source_address = 0x0;
		head_block.dest_address = (uint64_t) (uintptr_t) pkt_buffer_cap; /* cannot hand over the data buffer directly, it is task-restricted to us */
		head_block.block_size = XILINX_AXIENET_ETH_BUFFER_SIZE;
		head_block.next_block = NULL;
		head_block.source_addr_adj = DMA_ADDR_ADJ_INCREMENT;
		head_block.dest_addr_adj = DMA_ADDR_ADJ_INCREMENT;

		dma_conf.dma_slot = 0;
		dma_conf.channel_direction = PERIPHERAL_TO_MEMORY;
		dma_conf.complete_callback_en = 1;
		dma_conf.error_callback_dis = 0;
		dma_conf.block_count = 1;
		dma_conf.head_block = head_block_cap;
		dma_conf.user_data = (void *)dev;
		dma_conf.dma_callback = SKADI_SUBSYSTEM_FUNCTION_POINTER(xilinx_axienet_rx_callback);

		if (config->have_rx_csum_offload) {
			dma_conf.linked_channel = XILINX_AXI_DMA_LINKED_CHANNEL_FULL_CSUM_OFFLOAD;
		} else {
			dma_conf.linked_channel = XILINX_AXI_DMA_LINKED_CHANNEL_NO_CSUM_OFFLOAD;
		}

		if (!config->dma) {
			LOG_ERR("DMA handle is not provided in device tree!");
			k_panic();
		}

		err = dma_config(config->dma, XILINX_AXI_DMA_RX_CHANNEL_NUM, dma_conf_cap);
		skadi_cap_ops_drop(dma_conf_cap);
		skadi_cap_ops_drop(head_block_cap);
		if (err) {
			LOG_ERR("DMA config failed: %d", err);
			k_panic();
			return err;
		}

		data->dma_is_configured_rx = true;
	} else {
		/* can use faster "reload" API, as everything else stays the same */
		err = dma_reload(config->dma, XILINX_AXI_DMA_RX_CHANNEL_NUM, 0x0,
				 (uint64_t) rx_buffer_cap[current_descriptor], XILINX_AXIENET_ETH_BUFFER_SIZE);
		if (err) {
			LOG_ERR("DMA reconfigure failed: %d", err);
			k_panic();
			return err;
		}
	}
	LOG_DBG("Transmitting one packet with DMA!");

	/* prevent concurrent modification */
	data->rx_populated_buffer_index = next_descriptor;

	return 0;
}

static void xilinx_axienet_isr(const struct device *dev)
{
	const struct xilinx_axienet_config *config = dev->config;
	struct xilinx_axienet_data *data = dev->data;
	uint32_t status =
		xilinx_axienet_read_register(config, XILINX_AXIENET_INTERRUPT_PENDING_OFFSET);

	(void)data;

	/* TODO error counter not supported */
	if (status & XILINX_AXIENET_INTERRUPT_PENDING_RXFIFOOVR_MASK) {
		LOG_INF("FIFO was overrun!");
	} else if (status & XILINX_AXIENET_INTERRUPT_PENDING_RXREJ_MASK) {
		LOG_WRN("Erroneous frame received!");
	} else {
		LOG_ERR("Unknown interrupt status %"PRIu32, status);
	}

	/* clear IRQ by writing all bits */
	xilinx_axienet_write_register(config, XILINX_AXIENET_INTERRUPT_STATUS_OFFSET, -1);
	
}
#ifdef CONFIG_SKADI_OS
	#define DT_DRV_COMPAT xlnx_axi_ethernet_7_2
	
	SKADI_GENERATE_IRQ_HANDLER_WRAPPER(xilinx_axienet_isr)	

	#undef DT_DRV_COMPAT
	#define DT_DRV_COMPAT xlnx_axi_ethernet_1_00_a
	SKADI_GENERATE_IRQ_HANDLER_WRAPPER(xilinx_axienet_isr)	

	#undef DT_DRV_COMPAT
#endif

#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(enum ethernet_hw_caps, xilinx_axienet_get_capabilities, const struct device *device)
#else
static enum ethernet_hw_caps xilinx_axienet_get_capabilities(const struct device *device)
#endif
{
	const struct device *dev = skadi_get_own_device_representation(device);
	const struct xilinx_axienet_config *config = dev->config;
	enum ethernet_hw_caps ret = ETHERNET_LINK_10BASE_T | ETHERNET_LINK_100BASE_T |
				    ETHERNET_LINK_1000BASE_T | ETHERNET_HW_FILTERING;

	if (config->have_rx_csum_offload) {
		ret |= ETHERNET_HW_RX_CHKSUM_OFFLOAD;
	}
	if (config->have_tx_csum_offload) {
		ret |= ETHERNET_HW_TX_CHKSUM_OFFLOAD;
	}
#if defined(CONFIG_NET_L2_PTP)
	 if(config->ptp_clock){
		ret |= ETHERNET_PTP;
	 }
#endif

	return ret;
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axienet_get_capabilities)
#endif

#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, xilinx_axienet_get_config, const struct device *device, enum ethernet_config_type type,
				     struct ethernet_config *config)
#else
static int xilinx_axienet_get_config(const struct device *device, enum ethernet_config_type type,
				     struct ethernet_config *config)
#endif
{
	const struct device *dev = skadi_get_own_device_representation(device);
	const struct xilinx_axienet_config *dev_config = dev->config;
	const struct xilinx_axienet_data *data = dev->data;

	int err;

	__ASSERT(link_state != NULL, "Expected skadi link state to have been set!");

	switch (type) {
	case ETHERNET_CONFIG_TYPE_AUTO_NEG:
		/* enabled per default */
		config->auto_negotiation = true;
		return 0;
	case ETHERNET_CONFIG_TYPE_DUPLEX:
		err = skadi_phy_get_link_state(dev_config->phy, link_state);
		if (err != 0) {
			LOG_ERR("Failed to get link state: %d", err);
			return err;
		}
		config->full_duplex = link_state->is_up && (link_state->speed & LINK_FULL_10BASE_T ||
							   link_state->speed & LINK_FULL_100BASE_T ||
							   link_state->speed & LINK_FULL_1000BASE_T);
		return 0;
	case ETHERNET_CONFIG_TYPE_LINK:
		err = skadi_phy_get_link_state(dev_config->phy, link_state);
		if (err != 0) {
			LOG_ERR("Failed to get link state: %d", err);
			return err;
		}
		if (!link_state->is_up) {
			LOG_WRN("Ethernet is not up!");
			return -EAGAIN;
		}
		if (link_state->speed & LINK_HALF_10BASE_T ||
		    link_state->speed & LINK_FULL_10BASE_T) {
			config->l.link_10bt = true;
		}
		if (link_state->speed & LINK_HALF_100BASE_T ||
		    link_state->speed & LINK_FULL_100BASE_T) {
			config->l.link_100bt = true;
		}
		if (link_state->speed & LINK_HALF_1000BASE_T ||
		    link_state->speed & LINK_FULL_1000BASE_T) {
			config->l.link_1000bt = true;
		}
		return 0;
	case ETHERNET_CONFIG_TYPE_MAC_ADDRESS:
		memcpy(config->mac_address.addr, data->mac_addr, sizeof(data->mac_addr));
		return 0;
	case ETHERNET_CONFIG_TYPE_PROMISC_MODE:
		/* not supported yet */
		config->promisc_mode = false;
		return 0;
	case ETHERNET_CONFIG_TYPE_RX_CHECKSUM_SUPPORT:
		if (dev_config->have_rx_csum_offload) {
			config->chksum_support = ETHERNET_CHECKSUM_SUPPORT_IPV4_HEADER |
						 ETHERNET_CHECKSUM_SUPPORT_TCP |
						 ETHERNET_CHECKSUM_SUPPORT_UDP |
						 ETHERNET_CHECKSUM_SUPPORT_IPV6_HEADER |
						 ETHERNET_CHECKSUM_SUPPORT_TCP |
						 ETHERNET_CHECKSUM_SUPPORT_UDP;
		} else {
			config->chksum_support = ETHERNET_CHECKSUM_SUPPORT_NONE;
		}
		return 0;
	case ETHERNET_CONFIG_TYPE_TX_CHECKSUM_SUPPORT:
		if (dev_config->have_tx_csum_offload) {
			config->chksum_support = ETHERNET_CHECKSUM_SUPPORT_IPV4_HEADER |
						 ETHERNET_CHECKSUM_SUPPORT_TCP |
						 ETHERNET_CHECKSUM_SUPPORT_UDP |
						 ETHERNET_CHECKSUM_SUPPORT_IPV6_HEADER |
						 ETHERNET_CHECKSUM_SUPPORT_TCP |
						 ETHERNET_CHECKSUM_SUPPORT_UDP;
		} else {
			config->chksum_support = ETHERNET_CHECKSUM_SUPPORT_NONE;
		}
		return 0;
	default:
		LOG_ERR("Unsupported configuration queried: %u", type);
		return -EINVAL;
	}
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axienet_get_config)
#endif

uint8_t *mac_addr_cap;

#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, xilinx_axienet_iface_init, struct net_if *iface)
#else
static void xilinx_axienet_iface_init(struct net_if *iface)
#endif
{
	const struct device *dev = skadi_get_own_device_representation(net_if_get_device(iface));
	struct xilinx_axienet_data *data = dev->data;
	const struct xilinx_axienet_config *config = dev->config;
	long mask;

	__ASSERT(mac_addr_cap != NULL, "Assumed mac address to have been set!");

	data->interface = iface;

	skadi_ethernet_init(iface);

	skadi_net_if_set_link_addr(iface, mac_addr_cap, sizeof(data->mac_addr), NET_LINK_ETHERNET);

	/* if the ISR fires here, we will have inconsistent data */
	mask = dma_xilinx_axi_dma_channel_inhibit(config->dma, XILINX_AXI_DMA_RX_CHANNEL_NUM);

	LOG_INF("DMA start rx - mstatus 0x%lx!", csr_read(mstatus));

	for(int i = 0; i < CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX - 1; i ++){
		/* DMA needs to be ready to take care of incoming transmissions when we enable RX */
		setup_dma_rx_transfer(dev, config, data);
	}

	dma_xilinx_axi_dma_channel_uninhibit(config->dma, XILINX_AXI_DMA_RX_CHANNEL_NUM, mask);

	LOG_INF("DMA start rx done - mstatus 0x%lx!", csr_read(mstatus));

	irq_unlock(mask);
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axienet_iface_init)
#endif

#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int,xilinx_axienet_send, const struct device *device, struct net_pkt *pkt)
#else
static int xilinx_axienet_send(const struct device *device, struct net_pkt *pkt)
#endif
{
	const struct device *dev = skadi_get_own_device_representation(device);
	struct xilinx_axienet_data *data = dev->data;
	const struct xilinx_axienet_config *config = dev->config;
	struct net_pkt_cursor *cursor = &pkt->cursor;
	size_t next_descriptor =
	(data->tx_populated_buffer_index + 1) % CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_TX;
	size_t current_descriptor = data->tx_populated_buffer_index;
	struct dma_block_config *block_config, *first_config=NULL;
	int block_count = 0;
	int err;
	struct dma_config dma_conf = {0}, *dma_conf_cap;
	void *cap_pointer;
	int frag_num = 0;
	skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
#if defined(CONFIG_NET_L2_PTP)
	bool wait_ptp = false;
	bool notify_ptp_subsys = false;
#endif

	/* these data structures are given to the DMA, so we need to use derive() to make them accessible */
	if(skadi_cap_ops_derive(&dma_conf, restriction, sizeof(dma_conf), skadi_get_capability_offset(&dma_conf), SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &cap_pointer) == false || cap_pointer == 0){
		LOG_ERR("Could not derive token for DMA config struct!");
		return -ENOMEM;
	}
	dma_conf_cap = (struct dma_config *) cap_pointer;
	if (next_descriptor == data->tx_completed_buffer_index) {
		LOG_ERR("Cannot start TX via DMA - populated buffer %zu will run into completed"
			" buffer %zu!",
			data->tx_populated_buffer_index, data->tx_completed_buffer_index);
		return -ENOSPC;
	}
	
	LOG_DBG("TX of packet %zu start!", current_descriptor);

	/* need to hold on to packet until TX complete */
	data->tx_buffer[current_descriptor] = skadi_net_pkt_ref(pkt);

	__ASSERT_NO_MSG(data->tx_buffer[current_descriptor]);

	block_config = NULL;

	for(int i = 0; i < CONFIG_ETH_XILINX_AXIENET_FRAGMENTS_MAX; i++){
		tx_packets_in_flight[current_descriptor].fragments[i].source_address = 0;
	}

	do{
		struct dma_block_config *config_ro_cap;
		const void *current_buffer_cap;
		int aligned_len = cursor->buf->len;

		block_config = &tx_packets_in_flight[current_descriptor].fragments[frag_num++];
		
		/* de facto read-only */
		config_ro_cap = (struct dma_block_config *) skadi_cap_ops_derive_arg_ro(block_config, sizeof(*block_config));

		__ASSERT_NO_MSG(config_ro_cap);

		if(frag_num > 1){
			tx_packets_in_flight[current_descriptor].fragments[frag_num-2].next_block = config_ro_cap;
		}
		else{
			first_config = (struct dma_block_config*) config_ro_cap;
		}

		/* TODO handle gracefully */
		if(frag_num > CONFIG_ETH_XILINX_AXIENET_FRAGMENTS_MAX){
			LOG_ERR("Too many fragments!");
			k_panic();
		}
		
		if(!cursor->buf->derive_len){
			LOG_DBG("Flushing block %p length %d",cursor->buf->data, cursor->buf->len);
			LOG_HEXDUMP_DBG(cursor->buf->data, cursor->buf->len, "Flushing block ");
			/* 
			 * need writable capability to flush, as this is technically a store
			 * for Skadi zero-copy, cannot write --> need to flush elsewhere
			 */
			(void)arch_dcache_flush_range(cursor->buf->data, cursor->buf->len);
		}
		current_buffer_cap = skadi_cap_ops_derive_arg_ro(cursor->buf->data, aligned_len);

		__ASSERT(((uintptr_t) cursor->buf->data) % sizeof(void*) == ((uintptr_t) current_buffer_cap) % sizeof(void*), "Buffer %p has different alignment than cap %p!", cursor->buf->data, current_buffer_cap);

		__ASSERT_NO_MSG(current_buffer_cap);

		if(!current_buffer_cap){
			LOG_WRN("Could not derive buffer cap!");
			return -ENOMEM;
		}

		block_config->source_address = (uint64_t) (uintptr_t) current_buffer_cap;
		block_config->dest_address = 0x0; /* cannot hand over the data buffer directly, it is task-restricted to us */
		block_config->block_size = cursor->buf->len;
		block_config->next_block = NULL;
		block_config->source_addr_adj = DMA_ADDR_ADJ_INCREMENT;
		block_config->dest_addr_adj = DMA_ADDR_ADJ_INCREMENT;

		block_count++;

		LOG_DBG("Adding block %d with cap %p length %d\n", block_count, current_buffer_cap, cursor->buf->len);
	} while(skadi_net_pkt_cursor_advance(cursor));


	__ASSERT(dma_conf_cap != NULL, "DMA config capability should have been set!");

	dma_conf.dma_slot = 0;
	dma_conf.channel_direction = MEMORY_TO_PERIPHERAL;
	dma_conf.complete_callback_en = 1;
	dma_conf.error_callback_dis = 0;
	dma_conf.block_count = block_count;
	dma_conf.head_block = first_config;
	dma_conf.user_data = (void *)dev;
	dma_conf.dma_callback = SKADI_SUBSYSTEM_FUNCTION_POINTER(xilinx_axienet_tx_callback);

	if (config->have_tx_csum_offload) {
		dma_conf.linked_channel = XILINX_AXI_DMA_LINKED_CHANNEL_FULL_CSUM_OFFLOAD;
	} else {
		dma_conf.linked_channel = XILINX_AXI_DMA_LINKED_CHANNEL_NO_CSUM_OFFLOAD;
	}

	if (!config->dma) {
		LOG_ERR("DMA handle is not provided in device tree!");
		k_panic();
		return -EINVAL;
	}

#if defined(CONFIG_NET_L2_PTP)
	/* trigger on the LAST buffer - otherwise, might request TX timestamp before packet has even been buffered for TX */
	notify_ptp_subsys = xilinx_axienet_check_ptp(pkt);
	if(data->ha1588_was_reset && (notify_ptp_subsys || IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_TX))){
		wait_ptp = true;
		data->tx_timestamp_buf_index = current_descriptor;
		/* might not have been set... */	
		pkt->ll_proto_type = htons(NET_ETH_HDR(pkt)->type);
	}
#endif

	err = dma_config(config->dma, XILINX_AXI_DMA_TX_CHANNEL_NUM, dma_conf_cap);

	(void)skadi_cap_ops_drop(dma_conf_cap);

	for(int i = 0; i < frag_num; i++){
		if(tx_packets_in_flight[current_descriptor].fragments[i].next_block){
			(void)skadi_cap_ops_drop(tx_packets_in_flight[current_descriptor].fragments[i].next_block);
		}
	}
	(void)skadi_cap_ops_drop(first_config);

	if (err) {
		LOG_ERR("DMA config failed: %d", err);
		k_panic();
		return err;
	}

	data->tx_populated_buffer_index = next_descriptor;

	LOG_DBG("TX complete!\n");

#if defined(CONFIG_NET_L2_PTP)
	 if(wait_ptp){
		int ret;
		ret = skadi_sem_take(&data->tx_tstamp_available, K_FOREVER);
		/* should not fail with K_FOREVER */
		__ASSERT(!ret, "Could not wait for semaphore!");
		if(data->tx_timestamp_status == 0){
			memcpy(&pkt->timestamp, &data->tx_timestamp, sizeof(pkt->timestamp));
			skadi_net_if_add_tx_timestamp(pkt);
			ret = data->tx_timestamp_status;
		}
		else{
			LOG_ERR("TX timestamping failed: %d", data->tx_timestamp_status);
		}
	}
#endif

	/* completed */
	return err;
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axienet_send)
#endif

static void xilinx_axienet_set_mac_address(const struct xilinx_axienet_config *config,
					   const struct xilinx_axienet_data *data)
{
	xilinx_axienet_write_register(config, XILINX_AXIENET_UNICAST_ADDRESS_WORD_0_OFFSET,
				      (data->mac_addr[0]) | (data->mac_addr[1] << 8) |
					      (data->mac_addr[2] << 16) |
					      (data->mac_addr[3] << 24));
	xilinx_axienet_write_register(config, XILINX_AXIENET_UNICAST_ADDRESS_WORD_1_OFFSET,
				      (data->mac_addr[4]) | (data->mac_addr[5] << 8));
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, phy_link_state_changed, const struct device *dev, struct phy_link_state *state,
				   void *user_data)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(user_data);

	if(state->is_up){
#ifdef CONFIG_PTP_CLOCK_HA1588
		const struct device *if_dev = skadi_get_own_device_representation(user_data);
		const struct xilinx_axienet_config *config = if_dev->config; 
		struct xilinx_axienet_data *data = if_dev->data;

		__ASSERT_NO_MSG(if_dev);
		__ASSERT_NO_MSG(config);
		__ASSERT_NO_MSG(data);
		if(config->have_ha1588_tsu){
			int err;
			__ASSERT_NO_MSG(config->ptp_clock);
			skadi_ptp_tsu_ha1588_reset(config->ptp_clock);
			LOG_INF("ha1588 FIFOs reset!");

			/* we can only configer the TSU AFTER the reset*/

			err = skadi_ptp_tsu_ha1588_set_timestamp_all_rx(config->ptp_clock, IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_RX));
			if(err){
				LOG_ERR("Could not setup ha1588 RX timestamping for all packets: %s (%d)!", strerror(-err), -err);
				return;
			}

			err = skadi_ptp_tsu_ha1588_set_timestamp_all_tx(config->ptp_clock, IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_TX));
			if(err){
				LOG_ERR("Could not setup ha1588 TX timestamping for all packets: %s (%d)!", strerror(-err), -err);
				return;
			}

			data->ha1588_was_reset = true;
		}
#endif
		LOG_INF("Link state changed to: up (speed %x)", state->speed);
	}
	else{
		LOG_INF("Link state changed to: down (speed %x)", state->speed);
	}
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(phy_link_state_changed)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, setup_rx_buffers_timer, struct k_timer *timer)
	struct device *ethdev = timer->user_data;
	struct xilinx_axienet_data *data = ethdev->data;
	
	__ASSERT_NO_MSG(ethdev);
	__ASSERT_NO_MSG(data);
	
	for(int i = 0; i < data->failed_rx_setups; i++){
		/* might have been blocked due to packet being unavailable... */
		/* try again to make sure that RX buffers ARE available */
		if (setup_dma_rx_transfer(ethdev, ethdev->config, ethdev->data)) {
			LOG_DBG("Could not set up next RX DMA transfer in timer!");
			/* no point in proceeding */
			return;
		}
		else{
			data->failed_rx_setups--;
		}
	}

	if(!data->failed_rx_setups){
		skadi_timer_stop(&data->timer);
	}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(setup_rx_buffers_timer)

#if defined(CONFIG_NET_L2_PTP)
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(const struct device *, xilinx_axienet_get_ptp_clock, const struct device *dev)
	const struct xilinx_axienet_config *config = dev->config;

	return config->ptp_clock;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axienet_get_ptp_clock)
#endif /* CONFIG_PTP */

#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, xilinx_axienet_probe, const struct device *device)
#else
static int xilinx_axienet_probe(const struct device *device)
#endif
{	
	const struct device *dev = skadi_get_own_device_representation(device);
	const struct xilinx_axienet_config *config = dev->config;
	struct xilinx_axienet_data *data = dev->data;
	uint32_t status;
	int err;
	void* cap_pointer;
	skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

#if defined(CONFIG_NET_L2_PTP)
	data->tx_timestamp_buf_index = -1;
	skadi_sem_init(&data->tx_tstamp_available, 0, 1);

	LOG_INF("PTP clock %p have ha1588 %d", config->ptp_clock, config->have_ha1588_tsu);
#endif

	skadi_timer_init(&data->timer, SKADI_SUBSYSTEM_FUNCTION_POINTER(setup_rx_buffers_timer), NULL);

	data->timer.user_data = (void*) dev;

	link_state = skadi_allocator_alloc_rw(sizeof(*link_state));

	if(!link_state){
		LOG_ERR("Could not allocate link state!");
		return -ENOMEM;
	}

	/* network subsystem uses a reference to the address instead of copying the value... */
	if(skadi_cap_ops_derive(&data->mac_addr, restriction, sizeof(data->mac_addr), skadi_get_capability_offset(& data->mac_addr), SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &cap_pointer) == false || cap_pointer == 0){
		LOG_ERR("Could not derive token for MAC address!");
		return -ENOMEM;
	}
	mac_addr_cap = (uint8_t *) cap_pointer;

	status = xilinx_axienet_read_register(
		config, XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET);
	status = status & ~XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_RX_EN_MASK;
	xilinx_axienet_write_register(
		config, XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET, status);

	/* RX disabled - it is safe to modify settings */

	/* clear any RX rejected interrupts from when the core was not configured */
	xilinx_axienet_write_register(
		config, XILINX_AXIENET_INTERRUPT_STATUS_OFFSET,
		XILINX_AXIENET_INTERRUPT_STATUS_RXREJ_MASK |
			XILINX_AXIENET_INTERRUPT_STATUS_RXFIFOOVR_MASK);
	
	/* no interrupts until configured */
	xilinx_axienet_write_register(config, XILINX_AXIENET_INTERRUPT_ENABLE_OFFSET, 0);

	xilinx_axienet_write_register(config,
				      XILINX_AXIENET_RECEIVER_CONFIGURATION_FLOW_CONTROL_OFFSET,
				      XILINX_AXIENET_RECEIVER_CONFIGURATION_FLOW_CONTROL_EN_MASK);

	/* TODO trying to configure the PHY state here causes a crash in Skadi later on, I am not sure why... */

	__ASSERT(link_state != NULL, "Expected link state to have been set!");
	/* need a writable capability ... */
	err = skadi_phy_get_link_state(config->phy, link_state);

	if (!config->phy || err) {
		LOG_ERR("Could not get PHY link state: %d", config->phy ? err : -1);
	} else {
		if(link_state->is_up){
			LOG_INF("Current link state: up (speed %x)", link_state->speed);
		}
		else{
			LOG_INF("Current link state: down (speed %x)", link_state->speed);
		}
	}
	err = skadi_phy_link_callback_set(config->phy, SKADI_SUBSYSTEM_FUNCTION_POINTER(phy_link_state_changed), (void*)device);

	if (!config->phy || err) {
		LOG_ERR("Could not set PHY link state changed handler : %d",
			config->phy ? err : -1);
	}
	if (config->have_rx_csum_offload) {
		LOG_INF("RX Checksum offloading requested!");
	} else {
		LOG_INF("RX Checksum offloading disabled!");
	}

	if (config->have_tx_csum_offload) {
		LOG_INF("TX Checksum offloading requested!");
	} else {
		LOG_INF("TX Checksum offloading disabled!");
	}

	xilinx_axienet_set_mac_address(config, data);


	status = xilinx_axienet_read_register(
		config, XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET);
	status = status | XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_RX_EN_MASK;
	xilinx_axienet_write_register(
		config, XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET, status);

	status = xilinx_axienet_read_register(config, XILINX_AXIENET_TX_CONTROL_REG_OFFSET);
	status = status | XILINX_AXIENET_TX_CONTROL_TX_EN_MASK;
	xilinx_axienet_write_register(config, XILINX_AXIENET_TX_CONTROL_REG_OFFSET, status);

	__ASSERT(config && config->config_func, "Expected config and config func to be defined!");
	config->config_func(data);

	if(config->have_irq){
	xilinx_axienet_write_register(config, XILINX_AXIENET_INTERRUPT_ENABLE_OFFSET,
		 XILINX_AXIENET_INTERRUPT_ENABLE_RXREJ_MASK |
			  XILINX_AXIENET_INTERRUPT_ENABLE_OVR_MASK
		);
	}

	return 0;
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axienet_probe)
#endif

#ifdef CONFIG_SKADI_OS
	static int xilinx_axienet_probe_wrapper(const struct device *device){
		/* wrapper will call us */
		return 0;
	}
#else
	static int xilinx_axienet_probe_wrapper(const struct device *device){
		return xilinx_axienet_probe(device);
	}
#endif

#ifndef CONFIG_SKADI_OS
static const struct ethernet_api xilinx_axienet_api = {
	/* TODO PTP not supported yet */
	.iface_api.init = xilinx_axienet_iface_init,
	.get_capabilities = xilinx_axienet_get_capabilities,
	.get_config = xilinx_axienet_get_config,
	.send = xilinx_axienet_send,
};
#endif

#if defined(CONFIG_NET_L2_PTP)
#define SETUP_PTP_CLOCKS(inst) 																	\
 .ptp_clock = DEVICE_DT_GET(DT_CLOCKS_CTLR(DT_DRV_INST(inst))),									\
 .have_ha1588_tsu = DT_PROP_OR(DT_CLOCKS_CTLR(DT_DRV_INST(inst)), ha1588_tsu, false)
#else
#define SETUP_PTP_CLOCKS(inst)
#endif

#ifndef CONFIG_SKADI_OS
#define SETUP_IRQS(inst)                                                                           \
	IRQ_CONNECT(DT_INST_IRQN(inst), DT_INST_IRQ(inst, priority), xilinx_axienet_isr,           \
		    DEVICE_DT_INST_GET(inst), 0);                                                  \
                                                                                                   \
	irq_enable(DT_INST_IRQN(inst))
	/* in skadi case, probe is called externally via stub */
	/* otherwise, found + called by iterating section */
#define XILINX_AXIENET_INIT(inst)                                                                  \
                                                                                                   \
	static void xilinx_axienet_config_##inst(const struct xilinx_axienet_data *dev)            \
	{                                                                                          \
		COND_CODE_1(DT_INST_NODE_HAS_PROP(inst, interrupts), (SETUP_IRQS(inst)),           \
			    (LOG_INF("No IRQs defined!")));                                        \
	}                                                                                          \
                                                                                                   \
	static struct xilinx_axienet_data data_##inst = {                                          \
		.mac_addr = DT_INST_PROP(inst, local_mac_address)										\
	};                                                    \
	static const struct xilinx_axienet_config config_##inst = {                                \
		.config_func = xilinx_axienet_config_##inst,                                       \
		.dma = DEVICE_DT_GET(DT_INST_PHANDLE(inst, axistream_connected)),                  \
		.phy = DEVICE_DT_GET(DT_INST_PHANDLE(inst, phy_handle)),                           \
		.reg = (void *)(uintptr_t)DT_REG_ADDR(DT_INST_PARENT(inst)),                                  \
		.have_irq = DT_INST_NODE_HAS_PROP(inst, interrupts),                               \
		.have_tx_csum_offload = DT_INST_PROP_OR(inst, xlnx_txcsum, 0x0) == 0x2,            \
		.have_rx_csum_offload = DT_INST_PROP_OR(inst, xlnx_rxcsum, 0x0) == 0x2,				\
		SETUP_PTP_CLOCKS(inst)            \
	};                                                                                         \
                                                                                                   \
	ETH_NET_DEVICE_DT_INST_DEFINE(inst, xilinx_axienet_probe_wrapper, NULL, &data_##inst,              \
				      &config_##inst, CONFIG_ETH_INIT_PRIORITY,                    \
				      &xilinx_axienet_api, NET_ETH_MTU);

#else
#define SETUP_IRQS(inst)     \
	LOG_INF("Registering interrupt handler!");	\
	if(skadi_register_interrupt_handler(DT_INST_IRQN(inst), NULL, SKADI_IRQ_HANDLER_FUNCTION_POINTER(inst,xilinx_axienet_isr)) == false){	\
		LOG_ERR("Could not register ISR handler!");																							\
	}																																		\
	LOG_INF("Registered interrupt handler - enabling interrupt!");	\
	skadi_irq_enable(DT_INST_IRQN(inst), SKADI_IRQ_PRIORITY_DEFAULT);

	/* for Skadi, we only need a "normal" device declaration */
	/* registration as a network device is taken care off by our stub */	
#define XILINX_AXIENET_INIT(inst)                                                                  \
                                                                                                   \
	static void xilinx_axienet_config_##inst(const struct xilinx_axienet_data *dev)            \
	{                                                                                          \
		COND_CODE_1(DT_INST_NODE_HAS_PROP(inst, interrupts), (SETUP_IRQS(inst)),           \
			    (LOG_INF("No IRQs defined!")));                                        \
	}                                                                                          \
                                                                                                   \
	static struct xilinx_axienet_data data_##inst = {                                          \
		.mac_addr = DT_INST_PROP(inst, local_mac_address)										\
	};                                                    \
	static const struct xilinx_axienet_config config_##inst = {                                \
		.config_func = xilinx_axienet_config_##inst,                                       \
		.dma = DEVICE_DT_GET(DT_INST_PHANDLE(inst, axistream_connected)),                  \
		.phy = DEVICE_DT_GET(DT_INST_PHANDLE(inst, phy_handle)),                           \
		.reg = (void *)(uintptr_t)DT_REG_ADDR(DT_INST_PARENT(inst)),                                  \
		.have_irq = DT_INST_NODE_HAS_PROP(inst, interrupts),                               \
		.have_tx_csum_offload = DT_INST_PROP_OR(inst, xlnx_txcsum, 0x0) == 0x2,            \
		.have_rx_csum_offload = DT_INST_PROP_OR(inst, xlnx_rxcsum, 0x0) == 0x2,	\
		SETUP_PTP_CLOCKS(inst)            													\
	};                                                                                         \
                                                                                                   \
	DEVICE_DT_INST_DEFINE(inst, xilinx_axienet_probe_wrapper, NULL, &data_##inst,              \
				      &config_##inst, PRE_KERNEL_1, CONFIG_ETH_INIT_PRIORITY,                    \
				      NULL);
#endif

/* two different compatibles match the very same Ethernet core */

#define DT_DRV_COMPAT xlnx_axi_ethernet_7_2
DT_INST_FOREACH_STATUS_OKAY(XILINX_AXIENET_INIT);

#undef DT_DRV_COMPAT
#define DT_DRV_COMPAT xlnx_axi_ethernet_1_00_a
DT_INST_FOREACH_STATUS_OKAY(XILINX_AXIENET_INIT);

#undef DT_DRV_COMPAT

/* need devices to have been defined */
#if defined(CONFIG_SKADI_OS) && defined(CONFIG_SKADI_LOADER)

const static struct device *skadi_get_own_device_representation(const struct device *dev){
    const struct device *ret = NULL;
	const int device_node_id = device_get_dt_id(dev);

	#define DT_DRV_COMPAT xlnx_axi_ethernet_7_2
	SKADI_GET_OWN_DEVICE_REPRESENTATION(device_node_id)

	#undef DT_DRV_COMPAT
	#define DT_DRV_COMPAT xlnx_axi_ethernet_1_00_a
	SKADI_GET_OWN_DEVICE_REPRESENTATION(device_node_id)

	#undef DT_DRV_COMPAT


    __ASSERT(ret != NULL, "should be able to resolve the device I was given by other subsystem");

    return ret;
}
#else
const static struct device *skadi_get_own_device_representation(const struct device *dev){
    // one binary
    return dev;   
}
#endif

