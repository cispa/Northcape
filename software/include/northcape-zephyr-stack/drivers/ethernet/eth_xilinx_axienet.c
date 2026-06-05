/*
 * Xilinx AXI 1G / 2.5G Ethernet Subsystem
 *
 * 
 * SPDX-License-Identifier: Apache-2.0
 */

 #include <zephyr/logging/log.h>
 LOG_MODULE_REGISTER(eth_xilinx_axienet, CONFIG_ETHERNET_LOG_LEVEL);

 #include <sys/types.h>
 #include <zephyr/kernel.h>
 #include <zephyr/net/ethernet.h>
 #include <ethernet/eth_stats.h>
 #include <zephyr/drivers/dma.h>
 #include <zephyr/net/phy.h>
 #include <zephyr/irq.h>
 #include <zephyr/sys/barrier.h>

 #if defined(CONFIG_NET_L2_PTP)
 #include <zephyr/net/gptp.h>
 #include <zephyr/drivers/ptp_clock.h>
 #include <zephyr/drivers/ptp/ptp_clock_ha1588.h>
 #endif
 #include <zephyr/arch/cache.h>

 
 #include "../dma/dma_xilinx_axi_dma.h"
 
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
 
 #define XILINX_AXIENET_INTERRUPT_ENABLE_OFFSET     0x00000014
 #define XILINX_AXIENET_INTERRUPT_ENABLE_RXREJ_MASK 0x00000008
 #define XILINX_AXIENET_INTERRUPT_ENABLE_OVR_MASK   0x00000010 /* FIFO overrun */
 
 #define XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_0_REG_OFFSET     0x00000400
 #define XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET     0x00000404
 #define XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_RX_EN_MASK 0x10000000
 #define XILINX_AXIENET_RECEIVER_CONFIGURATION_FLOW_CONTROL_OFFSET   0x0000040C
 #define XILINX_AXIENET_RECEIVER_CONFIGURATION_FLOW_CONTROL_EN_MASK  0x20000000
 #define XILINX_AXIENET_TX_CONTROL_REG_OFFSET                        0x00000408
 #define XILINX_AXIENET_TX_CONTROL_TX_EN_MASK                        (1 << 11)
 
 #define XILINX_AXIENET_UNICAST_ADDRESS_WORD_0_OFFSET 0x00000700
 #define XILINX_AXIENET_UNICAST_ADDRESS_WORD_1_OFFSET 0x00000704
 
 #if (CONFIG_DCACHE_LINE_SIZE > 0)
 /* cache-line aligned to allow selective cache-line invalidation on the buffer */
 #define XILINX_AXIENET_ETH_ALIGN CONFIG_DCACHE_LINE_SIZE
 #else
 /* pointer-aligned to reduce padding in the struct */
 #define XILINX_AXIENET_ETH_ALIGN sizeof(void *)
 #endif
 
 #define XILINX_AXIENET_ETH_BUFFER_SIZE                                                             \
	 ((NET_ETH_MAX_FRAME_SIZE + XILINX_AXIENET_ETH_ALIGN - 1) & ~(XILINX_AXIENET_ETH_ALIGN - 1))
 
 struct xilinx_axienet_buffer {
	 uint8_t buffer[XILINX_AXIENET_ETH_BUFFER_SIZE];
 } __aligned(XILINX_AXIENET_ETH_ALIGN);
 
 /* device state */
 struct xilinx_axienet_data {
	 struct xilinx_axienet_buffer tx_buffer[CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_TX];
	 struct xilinx_axienet_buffer rx_buffer[CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX];

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

#endif
 
	 size_t rx_populated_buffer_index;
	 size_t rx_completed_buffer_index;
	 size_t tx_populated_buffer_index;
	 size_t tx_completed_buffer_index;
 
	 struct net_if *interface;
 
	 /* device mac address */
	 uint8_t mac_addr[NET_ETH_ADDR_LEN];
	 bool dma_is_configured_rx;
	 bool dma_is_configured_tx;
 };
 
 /* global configuration per Ethernet device */
 struct xilinx_axienet_config {
	 void (*config_func)(const struct xilinx_axienet_data *dev);
	 const struct device *dma;
 
	 const struct device *phy;

#if defined(CONFIG_NET_L2_PTP)
	 const struct device *ptp_clock;
#endif
 
	 mem_addr_t reg;
 
	 int irq_num;
	 bool have_irq;
 
	 bool have_rx_csum_offload;
	 bool have_tx_csum_offload;
#if defined(CONFIG_NET_L2_PTP)
	bool have_ha1588_tsu;
#endif
 };

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
 
 static void xilinx_axienet_write_register(const struct xilinx_axienet_config *config,
					   mem_addr_t reg_offset, uint32_t value)
 {
	 sys_write32(value, config->reg + reg_offset);
 }
 
 static uint32_t xilinx_axienet_read_register(const struct xilinx_axienet_config *config,
						  mem_addr_t reg_offset)
 {
	 return sys_read32(config->reg + reg_offset);
 }
 static int setup_dma_rx_transfer(const struct device *dev,
				  const struct xilinx_axienet_config *config,
				  struct xilinx_axienet_data *data);
 
 /* called by DMA when a packet is available */
 static void xilinx_axienet_rx_callback(const struct device *dma, void *user_data, uint32_t channel,
						int status)
 {
	 struct device *ethdev = (struct device *)user_data;
	 struct xilinx_axienet_data *data = ethdev->data;
	 unsigned int packet_size;
	 struct net_pkt *pkt;
 
	 size_t next_descriptor =
		 (data->rx_completed_buffer_index + 1) % CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX;
	 size_t current_descriptor = data->rx_completed_buffer_index;
 
	 if (!net_if_is_up(data->interface)) {
		 /*
		  * cannot receive data now, so discard silently
		  * setup new transfer for when the interface is back up
		  */
		 goto setup_new_transfer;
	 }
 
	 if (status < 0) {
		 LOG_ERR("DMA RX error: %d", status);
		 eth_stats_update_errors_rx(data->interface);
		 goto setup_new_transfer;
	 }
 
	 data->rx_completed_buffer_index = next_descriptor;
 
	 packet_size = dma_xilinx_axi_dma_last_received_frame_length(dma);
	 pkt = net_pkt_rx_alloc_with_buffer(data->interface, packet_size, AF_UNSPEC, 0, K_NO_WAIT);
 
	 if (!pkt) {
		 LOG_ERR("Could not allocate a packet!");
		 goto setup_new_transfer;
	 }

	 (void)arch_dcache_invd_range(data->rx_buffer[current_descriptor].buffer, packet_size);

	 if (net_pkt_write(pkt, data->rx_buffer[current_descriptor].buffer, packet_size)) {
		 LOG_ERR("Could not write RX buffer into packet!");
		 net_pkt_unref(pkt);
		 goto setup_new_transfer;
	 }

#if defined(CONFIG_NET_L2_PTP)
	 /* invalid by default */
	 pkt->timestamp.nanosecond = UINT32_MAX;
	 pkt->timestamp.second = UINT64_MAX;

	if(ptp_tsu_ha1588_packet_matches_rx_filter(pkt) || IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_RX)){
		const struct xilinx_axienet_config *config = ethdev->config;
		int ret;
#ifdef CONFIG_PTP_CLOCK_HA1588
		if(config->have_ha1588_tsu && data->ha1588_was_reset){
			/* can use precise timestamp from ha1588 */
			struct ha1588_tsu_timestamp rx_timestamp;

			ret = ptp_tsu_ha1588_get_rx_tstamp(config->ptp_clock, &rx_timestamp);

			memcpy(&pkt->timestamp, &rx_timestamp, sizeof(pkt->timestamp));

			LOG_DBG("Got RX timestamp %"PRIu64".%"PRIu32, pkt->timestamp.second, pkt->timestamp.nanosecond);
		}
		else{
#endif /* CONFIG_PTP_CLOCK_HA1588 */
		/* must use software timestamp */
		ret = ptp_clock_get(config->ptp_clock, &pkt->timestamp);
#ifdef CONFIG_PTP_CLOCK_HA1588
		}
#endif /* CONFIG_PTP_CLOCK_HA1588 */

		if(data->ha1588_was_reset && ret){
			LOG_HEXDUMP_ERR(data->rx_buffer[current_descriptor].buffer, packet_size, "Failed to get RX timestamp for packet");
		}
		else{
			LOG_HEXDUMP_DBG(data->rx_buffer[current_descriptor].buffer, packet_size, "Got RX timestamp for packet");
		}
	}
#endif

	 if (net_recv_data(data->interface, pkt) < 0) {
		 LOG_ERR("Coult not receive packet data!");
		 net_pkt_unref(pkt);
		 goto setup_new_transfer;
	 }
 
	 LOG_DBG("Packet with %u bytes received!\n", packet_size);
 
	 /* we need to start a new DMA transfer irregardless of whether the DMA reported an error */
	 /* otherwise, the ethernet subsystem would just stop receiving */
 setup_new_transfer:
	 if (setup_dma_rx_transfer(ethdev, ethdev->config, ethdev->data)) {
		 LOG_ERR("Could not set up next RX DMA transfer!");
	 }
 }
 
 static void xilinx_axienet_tx_callback(const struct device *dev, void *user_data, uint32_t channel,
						int status)
 {
	 struct device *ethdev = (struct device *)user_data;
	 struct xilinx_axienet_data *data = ethdev->data;
	 size_t next_descriptor =
		 (data->tx_completed_buffer_index + 1) % CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_TX;
	
#if defined(CONFIG_NET_L2_PTP)
	 if(data->tx_completed_buffer_index == data->tx_timestamp_buf_index){
		int ret;
		const struct xilinx_axienet_config *config = ethdev->config;
		/* this packet needs a tx time */
#ifdef CONFIG_PTP_CLOCK_HA1588
		if(config->have_ha1588_tsu){
			/* can use precise timestamp from ha1588 */
			struct ha1588_tsu_timestamp tx_timestamp;

			ret = ptp_tsu_ha1588_get_tx_tstamp(config->ptp_clock, &tx_timestamp);

			memcpy(&data->tx_timestamp, &tx_timestamp.tm, sizeof(data->tx_timestamp));
		}
		else{
#endif /* CONFIG_PTP_CLOCK_HA1588 */
		/* must use software timestamp */
		ret = ptp_clock_get(config->ptp_clock, &data->tx_timestamp);
#ifdef CONFIG_PTP_CLOCK_HA1588
		}
#endif /* CONFIG_PTP_CLOCK_HA1588 */
		data->tx_timestamp_status = ret;
		k_sem_give(&data->tx_tstamp_available);
	 }
#endif
		 
	 data->tx_completed_buffer_index = next_descriptor;
	 
	 if (status < 0) {
		 LOG_ERR("DMA TX error: %d", status);
		 eth_stats_update_errors_tx(data->interface);
	 }
 }
 
 static int setup_dma_rx_transfer(const struct device *dev,
				  const struct xilinx_axienet_config *config,
				  struct xilinx_axienet_data *data)
 {
	 int err;
	 size_t next_descriptor =
		 (data->rx_populated_buffer_index + 1) % CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX;
	 size_t current_descriptor = data->rx_populated_buffer_index;
 
	 if (next_descriptor == data->rx_completed_buffer_index) {
		 LOG_ERR("Cannot start RX via DMA - populated buffer %zu will run into completed"
			 " buffer %zu!",
			 data->rx_populated_buffer_index, data->rx_completed_buffer_index);
		 return -ENOSPC;
	 }
 
	 if (!data->dma_is_configured_rx) {
		 struct dma_block_config head_block = {
			 .source_address = 0x0,
			 .dest_address = (uintptr_t)data->rx_buffer[current_descriptor].buffer,
			 .block_size = sizeof(data->rx_buffer[current_descriptor].buffer),
			 .next_block = NULL,
			 .source_addr_adj = DMA_ADDR_ADJ_INCREMENT,
			 .dest_addr_adj = DMA_ADDR_ADJ_INCREMENT};
		 struct dma_config dma_conf = {.dma_slot = 0,
						   .channel_direction = PERIPHERAL_TO_MEMORY,
						   .complete_callback_en = 1,
						   .error_callback_dis = 0,
						   .block_count = 1,
						   .head_block = &head_block,
						   .user_data = (void *)dev,
						   .dma_callback = xilinx_axienet_rx_callback};
 
		 if (config->have_rx_csum_offload) {
			 dma_conf.linked_channel = XILINX_AXI_DMA_LINKED_CHANNEL_FULL_CSUM_OFFLOAD;
		 } else {
			 dma_conf.linked_channel = XILINX_AXI_DMA_LINKED_CHANNEL_NO_CSUM_OFFLOAD;
		 }
 
		 err = dma_config(config->dma, XILINX_AXI_DMA_RX_CHANNEL_NUM, &dma_conf);
		 if (err) {
			 LOG_ERR("DMA config failed: %d", err);
			 return err;
		 }
 
		 data->dma_is_configured_rx = true;
	 } else {
		 /* can use faster "reload" API, as everything else stays the same */
		 err = dma_reload(config->dma, XILINX_AXI_DMA_RX_CHANNEL_NUM, 0x0,
				  (uintptr_t)data->rx_buffer[current_descriptor].buffer,
				  sizeof(data->rx_buffer[current_descriptor].buffer));
		 if (err) {
			 LOG_ERR("DMA reconfigure failed: %d", err);
			 return err;
		 }
	 }
	 LOG_DBG("Receiving one packet with DMA!");
 
	 /* prevent concurrent modification */
	 data->rx_populated_buffer_index = next_descriptor;
 
	 err = dma_start(config->dma, XILINX_AXI_DMA_RX_CHANNEL_NUM);
 
	 if (err) {
		 /* buffer has not been accepted by DMA */
		 data->rx_populated_buffer_index = current_descriptor;
	 }
 
	 return err;
 }
 
 /* assumes that the caller has set up data->tx_buffer */
 static int setup_dma_tx_transfer(const struct device *dev,
				  const struct xilinx_axienet_config *config,
				  struct xilinx_axienet_data *data, uint32_t buffer_len)
 {
	 int err;
	 size_t next_descriptor =
		 (data->tx_populated_buffer_index + 1) % CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_TX;
	 size_t current_descriptor = data->tx_populated_buffer_index;
 
	 if (next_descriptor == data->tx_completed_buffer_index) {
		 LOG_ERR("Cannot start TX via DMA - populated buffer %zu will run into completed"
			 " buffer %zu!",
			 data->tx_populated_buffer_index, data->tx_completed_buffer_index);
		 return -ENOSPC;
	 }

	 (void)arch_dcache_flush_range(data->tx_buffer[current_descriptor].buffer, buffer_len);
 
	 if (!data->dma_is_configured_tx) {
		 struct dma_block_config head_block = {
			 .source_address = (uintptr_t)data->tx_buffer[current_descriptor].buffer,
			 .dest_address = 0x0,
			 .block_size = buffer_len,
			 .next_block = NULL,
			 .source_addr_adj = DMA_ADDR_ADJ_INCREMENT,
			 .dest_addr_adj = DMA_ADDR_ADJ_INCREMENT};
		 struct dma_config dma_conf = {.dma_slot = 0,
						   .channel_direction = MEMORY_TO_PERIPHERAL,
						   .complete_callback_en = 1,
						   .error_callback_dis = 0,
						   .block_count = 1,
						   .head_block = &head_block,
						   .user_data = (void *)dev,
						   .dma_callback = xilinx_axienet_tx_callback};
 
		 if (config->have_tx_csum_offload) {
			 dma_conf.linked_channel = XILINX_AXI_DMA_LINKED_CHANNEL_FULL_CSUM_OFFLOAD;
		 } else {
			 dma_conf.linked_channel = XILINX_AXI_DMA_LINKED_CHANNEL_NO_CSUM_OFFLOAD;
		 }
 
		 err = dma_config(config->dma, XILINX_AXI_DMA_TX_CHANNEL_NUM, &dma_conf);
		 if (err) {
			 LOG_ERR("DMA config failed: %d", err);
			 return err;
		 }
 
		 data->dma_is_configured_tx = true;
	 } else {
		 /* can use faster "reload" API, as everything else stays the same */
		 err = dma_reload(config->dma, XILINX_AXI_DMA_TX_CHANNEL_NUM,
				  (uintptr_t)data->tx_buffer[current_descriptor].buffer, 0x0,
				  buffer_len);
		 if (err) {
			 LOG_ERR("DMA reconfigure failed: %d", err);
			 return err;
		 }
	 }
 
	 /* prevent concurrent modification */
	 data->tx_populated_buffer_index = next_descriptor;
 
	 err = dma_start(config->dma, XILINX_AXI_DMA_TX_CHANNEL_NUM);
 
	 if (err) {
		 /* buffer has not been accepted by DMA */
		 data->tx_populated_buffer_index = current_descriptor;
	 }
 
	 return err;
 }
 
 static void xilinx_axienet_isr(const struct device *dev)
 {
	 const struct xilinx_axienet_config *config = dev->config;
	 struct xilinx_axienet_data *data = dev->data;
	 uint32_t status =
		 xilinx_axienet_read_register(config, XILINX_AXIENET_INTERRUPT_PENDING_OFFSET);
 
	 (void)data;
 
	 if (status & XILINX_AXIENET_INTERRUPT_PENDING_RXFIFOOVR_MASK) {
		 LOG_WRN("FIFO was overrun - probably lost packets!");
		 eth_stats_update_errors_rx(data->interface);
	 } else if (status & XILINX_AXIENET_INTERRUPT_PENDING_RXRJECT_MASK) {
		 /* this is extremely rare on Ethernet */
		 /* most likely cause is mistake in FPGA configuration */
		 LOG_WRN("Erroneous frame received!");
		 eth_stats_update_errors_rx(data->interface);
	 }
 
	 if (status != 0) {
		 /* clear IRQ by writing the same value back */
		 xilinx_axienet_write_register(config, XILINX_AXIENET_INTERRUPT_STATUS_OFFSET,
						   status);
	 }
 }
 
 static enum ethernet_hw_caps xilinx_axienet_caps(const struct device *dev)
 {
	 const struct xilinx_axienet_config *config = dev->config;
	 enum ethernet_hw_caps ret = ETHERNET_LINK_10BASE_T | ETHERNET_LINK_100BASE_T |
					 ETHERNET_LINK_1000BASE_T;
 
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
 
 static const struct device *xilinx_axienet_get_phy(const struct device *dev)
 {
	 const struct xilinx_axienet_config *config = dev->config;
 
	 return config->phy;
 }
 
 static int xilinx_axienet_get_config(const struct device *dev, enum ethernet_config_type type,
					  struct ethernet_config *config)
 {
	 const struct xilinx_axienet_config *dev_config = dev->config;
 
	 switch (type) {
	 case ETHERNET_CONFIG_TYPE_RX_CHECKSUM_SUPPORT:
		 if (dev_config->have_rx_csum_offload) {
			 config->chksum_support =
				 ETHERNET_CHECKSUM_SUPPORT_IPV4_HEADER |
				 ETHERNET_CHECKSUM_SUPPORT_TCP | ETHERNET_CHECKSUM_SUPPORT_UDP |
				 ETHERNET_CHECKSUM_SUPPORT_IPV6_HEADER |
				 ETHERNET_CHECKSUM_SUPPORT_TCP | ETHERNET_CHECKSUM_SUPPORT_UDP;
		 } else {
			 config->chksum_support = ETHERNET_CHECKSUM_SUPPORT_NONE;
		 }
		 return 0;
	 case ETHERNET_CONFIG_TYPE_TX_CHECKSUM_SUPPORT:
		 if (dev_config->have_tx_csum_offload) {
			 config->chksum_support =
				 ETHERNET_CHECKSUM_SUPPORT_IPV4_HEADER |
				 ETHERNET_CHECKSUM_SUPPORT_TCP | ETHERNET_CHECKSUM_SUPPORT_UDP |
				 ETHERNET_CHECKSUM_SUPPORT_IPV6_HEADER |
				 ETHERNET_CHECKSUM_SUPPORT_TCP | ETHERNET_CHECKSUM_SUPPORT_UDP;
		 } else {
			 config->chksum_support = ETHERNET_CHECKSUM_SUPPORT_NONE;
		 }
		 return 0;
	 default:
		 LOG_ERR("Unsupported configuration queried: %u", type);
		 return -EINVAL;
	 }
 }
 
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
 
 static int xilinx_axienet_set_config(const struct device *dev, enum ethernet_config_type type,
					  const struct ethernet_config *config)
 {
	 const struct xilinx_axienet_config *dev_config = dev->config;
	 struct xilinx_axienet_data *data = dev->data;
 
	 switch (type) {
	 case ETHERNET_CONFIG_TYPE_MAC_ADDRESS:
		 memcpy(data->mac_addr, config->mac_address.addr, sizeof(data->mac_addr));
		 xilinx_axienet_set_mac_address(dev_config, data);
		 return net_if_set_link_addr(data->interface, data->mac_addr,
			 sizeof(data->mac_addr), NET_LINK_ETHERNET);
	 default:
		 LOG_ERR("Unsupported configuration set: %u", type);
		 return -EINVAL;
	 }
 }
 
 static void phy_link_state_changed(const struct device *dev, struct phy_link_state *state,
					void *user_data)
 {
	 const struct device *if_dev = user_data;
	 struct xilinx_axienet_data *data = if_dev->data; 
 
	 LOG_INF("Link state changed to: %s (speed %x)", state->is_up ? "up" : "down", state->speed);
 
	 /* inform the L2 driver about link event */
	 if (state->is_up) {
#ifdef CONFIG_PTP_CLOCK_HA1588
		const struct xilinx_axienet_config *config = if_dev->config;
		if(config->have_ha1588_tsu){
			int err;
			ptp_tsu_ha1588_reset(config->ptp_clock);
			LOG_INF("ha1588 FIFOs reset!");

			/* we can only configer the TSU AFTER the reset*/

			err = ptp_tsu_ha1588_set_timestamp_all_rx(config->ptp_clock, IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_RX));
			if(err){
				LOG_ERR("Could not setup ha1588 RX timestamping for all packets: %s (%d)!", strerror(-err), -err);
				return;
			}

			err = ptp_tsu_ha1588_set_timestamp_all_tx(config->ptp_clock, IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_TX));
			if(err){
				LOG_ERR("Could not setup ha1588 TX timestamping for all packets: %s (%d)!", strerror(-err), -err);
				return;
			}

			data->ha1588_was_reset = true;
		}
#endif
		 net_eth_carrier_on(data->interface);
	 } else {
		 net_eth_carrier_off(data->interface);
	 }
 }
 
 static void xilinx_axienet_iface_init(struct net_if *iface)
 {
	 struct xilinx_axienet_data *data = net_if_get_device(iface)->data;
	 const struct xilinx_axienet_config *config = net_if_get_device(iface)->config;
	 int err;
 
	 data->interface = iface;
 
	 ethernet_init(iface);
 
	 net_if_set_link_addr(iface, data->mac_addr, sizeof(data->mac_addr), NET_LINK_ETHERNET);
 
	 /* carrier is initially off */
	 net_eth_carrier_off(iface);
 
	 err = phy_link_callback_set(config->phy, phy_link_state_changed, (void*)net_if_get_device(iface));
 
	 if (err) {
		 LOG_ERR("Could not set PHY link state changed handler : %d",
			 config->phy ? err : -1);
	 }
 
	 LOG_INF("Interface initialized!");
 }
 
 static int xilinx_axienet_send(const struct device *dev, struct net_pkt *pkt)
 {
	 struct xilinx_axienet_data *data = dev->data;
	 const struct xilinx_axienet_config *config = dev->config;
	 size_t pkt_len = net_pkt_get_len(pkt);
	 size_t current_descriptor = data->tx_populated_buffer_index;
	 int ret;
#if defined(CONFIG_NET_L2_PTP)
	 bool wait_ptp = false;
	 bool notify_ptp_subsys = false;
#endif
 
	 if (net_pkt_read(pkt, data->tx_buffer[current_descriptor].buffer, pkt_len)) {
		 LOG_ERR("Failed to read packet into TX buffer!");
		 return -EIO;
	 }
#if defined(CONFIG_NET_L2_PTP)
	notify_ptp_subsys = xilinx_axienet_check_ptp(pkt);
	 if(data->ha1588_was_reset && (notify_ptp_subsys || IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_TX))){
		wait_ptp = true;
		data->tx_timestamp_buf_index = current_descriptor;
		/* might not have been set... */	
		pkt->ll_proto_type = htons(NET_ETH_HDR(pkt)->type);
	 }
#endif

	 ret = setup_dma_tx_transfer(dev, config, data, pkt_len);

#if defined(CONFIG_NET_L2_PTP)
	 if(wait_ptp){
		ret = k_sem_take(&data->tx_tstamp_available, K_FOREVER);
		/* should not fail with K_FOREVER */
		__ASSERT(!ret, "Could not wait for semaphore!");
		if(data->tx_timestamp_status == 0){
			memcpy(&pkt->timestamp, &data->tx_timestamp, sizeof(pkt->timestamp));
			net_if_add_tx_timestamp(pkt);
			ret = data->tx_timestamp_status;
		}
		else{
			LOG_ERR("TX timestamping failed: %d", data->tx_timestamp_status);
		}
	}
#endif

	 return ret;
 }
 
 static int xilinx_axienet_probe(const struct device *dev)
 {
	 const struct xilinx_axienet_config *config = dev->config;
	 struct xilinx_axienet_data *data = dev->data;
	 uint32_t status;
	 int err;

#if defined(CONFIG_NET_L2_PTP)
	 data->tx_timestamp_buf_index = -1;
	 k_sem_init(&data->tx_tstamp_available, 0, 1);
#endif
 
	 status = xilinx_axienet_read_register(
		 config, XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET);
	 status = status & ~XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_RX_EN_MASK;
	 xilinx_axienet_write_register(
		 config, XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET, status);
 
	 /* RX disabled - it is safe to modify settings */
 
	 /* clear any RX rejected interrupts from when the core was not configured */
	 xilinx_axienet_write_register(config, XILINX_AXIENET_INTERRUPT_STATUS_OFFSET,
					   XILINX_AXIENET_INTERRUPT_STATUS_RXREJ_MASK |
						   XILINX_AXIENET_INTERRUPT_STATUS_RXFIFOOVR_MASK);
 
	 xilinx_axienet_write_register(config, XILINX_AXIENET_INTERRUPT_ENABLE_OFFSET,
					   config->have_irq
						   ? XILINX_AXIENET_INTERRUPT_ENABLE_RXREJ_MASK |
							 XILINX_AXIENET_INTERRUPT_ENABLE_OVR_MASK
						   : 0);
 
	 xilinx_axienet_write_register(config,
					   XILINX_AXIENET_RECEIVER_CONFIGURATION_FLOW_CONTROL_OFFSET,
					   XILINX_AXIENET_RECEIVER_CONFIGURATION_FLOW_CONTROL_EN_MASK);
 
	 /* at time of writing, hardware does not support half duplex */
	 err = phy_configure_link(config->phy, LINK_FULL_10BASE_T | LINK_FULL_100BASE_T |
							   LINK_FULL_1000BASE_T);
	 if (err) {
		 LOG_WRN("Could not configure PHY: %d", -err);
	 }
 
	 LOG_INF("RX Checksum offloading %s",
		 config->have_rx_csum_offload ? "requested" : "disabled");
	 LOG_INF("TX Checksum offloading %s",
		 config->have_tx_csum_offload ? "requested" : "disabled");
 
	 xilinx_axienet_set_mac_address(config, data);
 
	 for (int i = 0; i < CONFIG_ETH_XILINX_AXIENET_BUFFER_NUM_RX - 1; i++) {
		 setup_dma_rx_transfer(dev, config, data);
	 }
 
	 status = xilinx_axienet_read_register(
		 config, XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET);
	 status = status | XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_RX_EN_MASK;
	 xilinx_axienet_write_register(
		 config, XILINX_AXIENET_RECEIVER_CONFIGURATION_WORD_1_REG_OFFSET, status);
 
	 status = xilinx_axienet_read_register(config, XILINX_AXIENET_TX_CONTROL_REG_OFFSET);
	 status = status | XILINX_AXIENET_TX_CONTROL_TX_EN_MASK;
	 xilinx_axienet_write_register(config, XILINX_AXIENET_TX_CONTROL_REG_OFFSET, status);
 
	 config->config_func(data);
 
	 return 0;
 }

 #if defined(CONFIG_NET_L2_PTP)
static const struct device *xilinx_axienet_get_ptp_clock(const struct device *dev)
{
	const struct xilinx_axienet_config *config = dev->config;

	return config->ptp_clock;
}
#endif /* CONFIG_PTP */
 
 /* TODO VLAN not supported yet */
 static const struct ethernet_api xilinx_axienet_api = {
	 .iface_api.init = xilinx_axienet_iface_init,
	 .get_capabilities = xilinx_axienet_caps,
	 .get_config = xilinx_axienet_get_config,
	 .set_config = xilinx_axienet_set_config,
	 .get_phy = xilinx_axienet_get_phy,
	 .send = xilinx_axienet_send,
#if defined(CONFIG_NET_L2_PTP)
	.get_ptp_clock		= xilinx_axienet_get_ptp_clock,
#endif
 };
 
 #define SETUP_IRQS(inst)                                                                           \
	 IRQ_CONNECT(DT_INST_IRQN(inst), DT_INST_IRQ(inst, priority), xilinx_axienet_isr,           \
			 DEVICE_DT_INST_GET(inst), 0);                                                  \
																									\
	 irq_enable(DT_INST_IRQN(inst))

#if defined(CONFIG_NET_L2_PTP)
#define SETUP_PTP_CLOCKS(inst) 																	\
 .ptp_clock = DEVICE_DT_GET(DT_CLOCKS_CTLR(DT_DRV_INST(inst))),									\
 .have_ha1588_tsu = DT_PROP_OR(DT_CLOCKS_CTLR(DT_DRV_INST(inst)), ha1588_tsu, false)
#else
#define SETUP_PTP_CLOCKS(inst)
#endif

 #define XILINX_AXIENET_INIT(inst)                                                                  \
																									\
	 static void xilinx_axienet_config_##inst(const struct xilinx_axienet_data *dev)            \
	 {                                                                                          \
		 COND_CODE_1(DT_INST_NODE_HAS_PROP(inst, interrupts), (SETUP_IRQS(inst)),           \
				 (LOG_INF("No IRQs defined!")));        \
	 }                                                                                          \
																									\
	 static struct xilinx_axienet_data data_##inst = {                                          \
		 .mac_addr = DT_INST_PROP(inst, local_mac_address),                                 \
		 .dma_is_configured_rx = false,                                                     \
		 .dma_is_configured_tx = false};                                                    \
	 static const struct xilinx_axienet_config config_##inst = {                                \
		 .config_func = xilinx_axienet_config_##inst,                                       \
		 .dma = DEVICE_DT_GET(DT_INST_PHANDLE(inst, axistream_connected)),                  \
		 .phy = DEVICE_DT_GET(DT_INST_PHANDLE(inst, phy_handle)),                           \
		 .reg = DT_REG_ADDR(DT_INST_PARENT(inst)),                                          \
		 .have_irq = DT_INST_NODE_HAS_PROP(inst, interrupts),                               \
		 .have_tx_csum_offload = DT_INST_PROP_OR(inst, xlnx_txcsum, 0x0) == 0x2,            \
		 .have_rx_csum_offload = DT_INST_PROP_OR(inst, xlnx_rxcsum, 0x0) == 0x2,            \
		 SETUP_PTP_CLOCKS(inst)																\
	 };                                                                                         \
																									\
	 ETH_NET_DEVICE_DT_INST_DEFINE(inst, xilinx_axienet_probe, NULL, &data_##inst,              \
					   &config_##inst, CONFIG_ETH_INIT_PRIORITY,                    \
					   &xilinx_axienet_api, NET_ETH_MTU);

/* within the constraints of this driver, these two variants of the IP work the same */
#define DT_DRV_COMPAT xlnx_axi_ethernet_3_00_a
DT_INST_FOREACH_STATUS_OKAY(XILINX_AXIENET_INIT);

#undef DT_DRV_COMPAT
#define DT_DRV_COMPAT xlnx_axi_ethernet_1_00_a
DT_INST_FOREACH_STATUS_OKAY(XILINX_AXIENET_INIT);
 
