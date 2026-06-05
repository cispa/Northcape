/*
 * Xilinx AXI Ethernet Lite driver
 *
 * 
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(eth_xilinx_axi_ethernet_lite, CONFIG_ETHERNET_LOG_LEVEL);

#define DT_DRV_COMPAT xlnx_xps_ethernetlite_3_00_a_mac

#include <zephyr/kernel.h>
#include <zephyr/net/ethernet.h>
#include <zephyr/net/phy.h>
#include "eth.h"

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_irq.h>
#include <zephyr/skadi/skadi_device.h>
#include <zephyr/skadi/skadi_timer.h>
#include <zephyr/skadi/skadi_sem.h>

#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/subsystems/net/skadi_ethernet_subsystem.h>
#include <zephyr/skadi/subsystems/net/skadi_phy.h>
#include <zephyr/skadi/subsystems/net/skadi_net.h>

#if defined(CONFIG_NET_L2_PTP)
#include <zephyr/net/gptp.h>
#include <zephyr/skadi/subsystems/ptp/skadi_ptp_clock.h>
#include <zephyr/skadi/subsystems/ptp/skadi_ptp_clock_ha1588.h>
#endif


/* memory-mapped dual-port RAM for TX */
#define XILINX_AXI_ETHERNET_LITE_TX_PING_START_REG_OFFSET 0x0000
#define XILINX_AXI_ETHERNET_LITE_TX_PING_END_REG_OFFSET   0x07F0

#define XILINX_AXI_ETHERNET_LITE_TX_PONG_START_REG_OFFSET 0x0800
#define XILINX_AXI_ETHERNET_LITE_TX_PONG_END_REG_OFFSET   0x0FFC

/* memory-mapped dual-port RAM for RX */
#define XILINX_AXI_ETHERNET_LITE_RX_PING_START_REG_OFFSET 0x1000
#define XILINX_AXI_ETHERNET_LITE_RX_PING_END_REG_OFFSET   0x17F0

#define XILINX_AXI_ETHERNET_LITE_RX_PONG_START_REG_OFFSET 0x1800
#define XILINX_AXI_ETHERNET_LITE_RX_PONG_END_REG_OFFSET   0x1FFC

#define XILINX_AXI_ETHERNET_LITE_TX_PING_LENGTH_REG_OFFSET 0x07F4
#define XILINX_AXI_ETHERNET_LITE_GIE_REG_OFFSET            0x07F8
#define XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_REG_OFFSET   0x07FC
#define XILINX_AXI_ETHERNET_LITE_TX_PONG_LENGTH_REG_OFFSET 0x0FF4
#define XILINX_AXI_ETHERNET_LITE_TX_PONG_CTRL_REG_OFFSET   0x0FFC
#define XILINX_AXI_ETHERNET_LITE_RX_PING_CTRL_REG_OFFSET   0x17FC
#define XILINX_AXI_ETHERNET_LITE_RX_PONG_CTRL_REG_OFFSET   0x1FFC

#define XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_PROGRAM_MAC_MASK (BIT(0) | BIT(1))
#define XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_BUSY_MASK        (BIT(0) | BIT(1))
/* transmit (bit 0) and interrupt enable (bit 3), loopback, program disabled */
#define XILINX_AXI_ETHERNET_LITE_TX_PING_TX_MASK               (BIT(0) | BIT(3))

#define XILINX_AXI_ETHERNET_LITE_RX_CTRL_IRQ_ENABLE_MASK   BIT(3)
#define XILINX_AXI_ETHERNET_LITE_RX_CTRL_READY_ENABLE_MASK BIT(0)

#define XILINX_AXI_ETHERNET_LITE_GIE_ENABLE_MASK BIT(31)

struct xilinx_axi_ethernet_lite_data {
	/* used between ISR and send routine */
	struct k_sem tx_sem;
	/* used to trigger the RX ISR from time to time */
	struct k_timer rx_timer;
	struct k_spinlock timer_lock;
	struct net_if *interface;

#ifdef CONFIG_NET_L2_PTP
	/* index of a data buffer whose net_pkt is currently waiting for a tx timestamp, or -1 if none */
	ssize_t tx_timestamp_buf_index;
	struct net_ptp_time tx_timestamp;
	struct k_sem tx_tstamp_available;
	int tx_timestamp_status;
#endif

	uint8_t mac_addr[NET_ETH_ADDR_LEN];
	bool tx_ping_toggle;
	bool rx_ping_toggle;

#ifdef CONFIG_PTP_CLOCK_HA1588
	bool ha1588_was_reset;
#endif /* CONFIG_PTP_CLOCK_HA1588 */
};
struct xilinx_axi_ethernet_lite_config {
	void (*config_func)(struct xilinx_axi_ethernet_lite_data *data);

	const struct device *phy;
	const uintptr_t reg;

#if defined(CONFIG_NET_L2_PTP)
	const struct device *ptp_clock;
#endif

    int irq_number;

	/* device tree properties */
	bool has_duplex;
	bool has_mdio;
	bool has_rx_ping_pong;
	bool has_tx_ping_pong;
	bool has_random_mac_address;
	bool has_interrupt;
#if defined(CONFIG_NET_L2_PTP)
	bool have_ha1588_tsu;
#endif
};

SKADI_DECLARE_DEVICE_REPRESENTATION_WRAPPER;

static inline uint32_t
xilinx_axi_ethernet_lite_read_reg(const struct xilinx_axi_ethernet_lite_config *config,
				  mem_addr_t reg)
{
	return sys_read32((mem_addr_t)config->reg + reg);
}

static inline void
xilinx_axi_ethernet_lite_write_reg(const struct xilinx_axi_ethernet_lite_config *config,
				   mem_addr_t reg, uint32_t value)
{
	sys_write32(value, (mem_addr_t)config->reg + reg);
}

static inline void
xilinx_axi_ethernet_lite_wait_complete(const struct xilinx_axi_ethernet_lite_config *config)
{
	while (xilinx_axi_ethernet_lite_read_reg(config,
						 XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_REG_OFFSET) &
	       XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_BUSY_MASK) {
		k_busy_wait(1);
	}
}

static inline void
xilinx_axi_ethernet_lite_write_transmit_buffer(const struct xilinx_axi_ethernet_lite_config *config,
					       mem_addr_t buffer_start, const uint8_t *data,
					       size_t data_length)
{
	uint32_t unaligned_buffer;
	const int start_offset = buffer_start & (sizeof(uint32_t) - 1);

	if (start_offset) {
		uint8_t *buffer_ptr;
		/*
		 * unaligned - write first bytes, keeping whatever was in the buffer already and
		 * restore alignment
		 */
		unaligned_buffer = xilinx_axi_ethernet_lite_read_reg(
			config, buffer_start & ~(sizeof(uint32_t) - 1));
		buffer_ptr = (uint8_t *)&unaligned_buffer;
		memcpy(&buffer_ptr[start_offset], data, sizeof(uint32_t) - start_offset);
		xilinx_axi_ethernet_lite_write_reg(config, buffer_start & ~(sizeof(uint32_t) - 1),
						   unaligned_buffer);
		buffer_start += sizeof(uint32_t) - start_offset;
		data += sizeof(uint32_t) - start_offset;
		data_length -= sizeof(uint32_t) - start_offset;
	}
	unaligned_buffer = 0;

	__ASSERT((buffer_start & (sizeof(uint32_t) - 1)) == 0, "Buffer addr %p is not aligned",
		 (void *)buffer_start);

	/* validity of length must be checked by caller! */
	while (data_length >= sizeof(uint32_t)) {
		/* in case of fragmented buffer, data alignment and output alignment might not match
		 */
		uint32_t transfer_buffer;

		memcpy(&transfer_buffer, data, sizeof(transfer_buffer));
		xilinx_axi_ethernet_lite_write_reg(config, buffer_start, transfer_buffer);
		data += sizeof(uint32_t);
		buffer_start += sizeof(uint32_t);
		data_length -= sizeof(uint32_t);
	}

	if (data_length) {
		memcpy(&unaligned_buffer, data, data_length);
		xilinx_axi_ethernet_lite_write_reg(config, buffer_start, unaligned_buffer);
	}
}

static inline void
xilinx_axi_ethernet_lite_program_mac_address(const struct xilinx_axi_ethernet_lite_config *config,
					     const struct xilinx_axi_ethernet_lite_data *data)
{
	/* ping buffer is always available, pong would be optional */
	xilinx_axi_ethernet_lite_write_transmit_buffer(
		config, XILINX_AXI_ETHERNET_LITE_TX_PING_START_REG_OFFSET, data->mac_addr,
		NET_ETH_ADDR_LEN);

	xilinx_axi_ethernet_lite_write_reg(config, XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_REG_OFFSET,
					   XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_PROGRAM_MAC_MASK);

	/* no interrupt configured - just spin */
	xilinx_axi_ethernet_lite_wait_complete(config);
}


SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(enum ethernet_hw_caps, xilinx_axi_eth_lite_get_capabilities, const struct device *orig_dev)
{
    enum ethernet_hw_caps ret = ETHERNET_LINK_10BASE_T | ETHERNET_LINK_100BASE_T;
#if defined(CONFIG_NET_L2_PTP)
	const struct xilinx_axi_ethernet_lite_config *config = skadi_get_own_device_representation(orig_dev)->config;

	if(config->ptp_clock){
		ret |= ETHERNET_PTP;
	}
#endif

	return ret;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axi_eth_lite_get_capabilities)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, xilinx_axi_eth_lite_get_config, const struct device *orig_dev, enum ethernet_config_type type,
				     struct ethernet_config *config)
    /* nothing supported, but our wrapper needs this */
    ARG_UNUSED(orig_dev);
    return -EINVAL;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axi_eth_lite_get_config)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, xilinx_axi_ethernet_lite_phy_link_state_changed, const struct device* phydev, struct phy_link_state *state, void *user_data)
{
	const struct device *if_dev = skadi_get_own_device_representation(user_data);
	struct xilinx_axi_ethernet_lite_data *data = if_dev->data;

	ARG_UNUSED(phydev);

	LOG_INF("Link state changed to: %s (speed %x)", state->is_up ? "up" : "down", state->speed);

	/* inform the L2 driver whether we can handle packets now */
	if (state->is_up) {
		skadi_net_eth_carrier_on(data->interface);
#ifdef CONFIG_PTP_CLOCK_HA1588
		const struct xilinx_axi_ethernet_lite_config *config = if_dev->config;
		if(config->have_ha1588_tsu){
			int err;
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
	} else {
		skadi_net_eth_carrier_off(data->interface);
	}
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axi_ethernet_lite_phy_link_state_changed)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, xilinx_axi_eth_lite_iface_init, struct net_if *iface)
{
    const struct device *dev = skadi_get_own_device_representation(net_if_get_device(iface));
	struct xilinx_axi_ethernet_lite_data *data = dev->data;
	const struct xilinx_axi_ethernet_lite_config *config = dev->config;
	int err;

	data->interface = iface;

	skadi_ethernet_init(iface);

	LOG_INF("Programming initial MAC address!");
	xilinx_axi_ethernet_lite_program_mac_address(config, data);
	if (skadi_net_if_set_link_addr(data->interface, (uint8_t*)skadi_cap_ops_derive_arg_ro(data->mac_addr, sizeof(data->mac_addr)), sizeof(data->mac_addr),
				 NET_LINK_ETHERNET)) {
		LOG_ERR("Could not set initial link address!");
	}
	LOG_INF("MAC address set!");

	if (config->phy) {
		/* initially no carrier */
		skadi_net_eth_carrier_off(iface);

		err = skadi_phy_link_callback_set(config->phy,
					    SKADI_SUBSYSTEM_FUNCTION_POINTER(xilinx_axi_ethernet_lite_phy_link_state_changed), (void*)dev);

		if (err) {
			LOG_ERR("Could not set PHY link state changed handler: %d", err);
		}
	} else {
		/* fixed link - no way to know so assume it is on */
		skadi_net_eth_carrier_on(iface);
	}

	if (CONFIG_ETH_XILINX_AXI_ETHERNET_LITE_TIMER_PERIOD) {
		skadi_timer_start(&data->rx_timer, K_MSEC(CONFIG_ETH_XILINX_AXI_ETHERNET_LITE_TIMER_PERIOD),
			      K_MSEC(CONFIG_ETH_XILINX_AXI_ETHERNET_LITE_TIMER_PERIOD));
	}

	xilinx_axi_ethernet_lite_write_reg(config, XILINX_AXI_ETHERNET_LITE_RX_PING_CTRL_REG_OFFSET,
					   XILINX_AXI_ETHERNET_LITE_RX_CTRL_IRQ_ENABLE_MASK);

	LOG_INF("Interface initialized!");
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axi_eth_lite_iface_init)

static inline bool xilinx_axi_ethernet_lite_cursor_advance(struct net_pkt_cursor *cursor)
{
	if (!cursor->buf->frags) {
		/* packet complete */
		return false;
	}
	cursor->buf = cursor->buf->frags;
	return true;
}

#if defined(CONFIG_NET_L2_PTP)
static bool axi_eth_lite_check_ptp(struct net_pkt *pkt){
	
	if(ntohs(NET_ETH_HDR(pkt)->type) == NET_ETH_PTYPE_PTP){
		return true;
	}

	if(pkt->ptp_pkt || pkt->tx_timestamping){
		return true;
	}

	return false;
}
#endif

#define AXI_ETH_LITE_TX_MAX_TSTAMP_TRIES 100


SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, xilinx_axi_eth_lite_send, const struct device *orig_dev, struct net_pkt *pkt)
{
    const struct device *dev = skadi_get_own_device_representation(orig_dev);
	const size_t mtu = NET_ETH_MTU + sizeof(struct net_eth_hdr);
	mem_addr_t buffer_addr, length_addr, control_addr;
	struct net_pkt_cursor *cursor = &pkt->cursor;
	struct xilinx_axi_ethernet_lite_data *data = dev->data;
	const struct xilinx_axi_ethernet_lite_config *config = dev->config;
#if defined(CONFIG_NET_L2_PTP)
	bool notify_ptp_subsys;
	bool wait_ptp = false;
#endif
	

	if (net_pkt_get_len(pkt) > mtu) {
		LOG_INF("Packet is too long: %zu bytes with MTU: %zu bytes!", net_pkt_get_len(pkt),
			mtu);
		return -EINVAL;
	}

	if (config->has_tx_ping_pong && data->tx_ping_toggle) {
		buffer_addr = XILINX_AXI_ETHERNET_LITE_TX_PONG_START_REG_OFFSET;
		length_addr = XILINX_AXI_ETHERNET_LITE_TX_PONG_LENGTH_REG_OFFSET;
		control_addr = XILINX_AXI_ETHERNET_LITE_TX_PONG_CTRL_REG_OFFSET;
	} else {
		buffer_addr = XILINX_AXI_ETHERNET_LITE_TX_PING_START_REG_OFFSET;
		length_addr = XILINX_AXI_ETHERNET_LITE_TX_PING_LENGTH_REG_OFFSET;
		control_addr = XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_REG_OFFSET;
	}

	if (config->has_interrupt) {
		(void)skadi_sem_take(&data->tx_sem, K_FOREVER);
	}

	if (xilinx_axi_ethernet_lite_read_reg(config, control_addr) &
	    XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_BUSY_MASK) {
		/*
		 * no interrupt -> try to transmit as many packets as the L2 wants, discard them if
		 * busy; otherwise, semaphore for flow control
		 */
		if (config->has_interrupt) {
			LOG_WRN("Unexpectedly, %s buffer is busy!",
				control_addr == XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_REG_OFFSET
					? "ping"
					: "pong");
		}

		return -EBUSY;
	}

#if defined(CONFIG_NET_L2_PTP)
	notify_ptp_subsys = axi_eth_lite_check_ptp(pkt);
	if(data->ha1588_was_reset && (notify_ptp_subsys || IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_TX))){
		wait_ptp = true;
		/* might not have been set... */	
		pkt->ll_proto_type = htons(NET_ETH_HDR(pkt)->type);
	}
#endif

	data->tx_ping_toggle = !data->tx_ping_toggle;

	/* no need to linearize - can copy fragments one by one into transmit buffer */
	do {
		int frag_len = cursor->buf->len;
		const uint8_t *frag_data = cursor->buf->data;

		xilinx_axi_ethernet_lite_write_transmit_buffer(config, buffer_addr, frag_data,
							       frag_len);

		buffer_addr += frag_len;
	} while (xilinx_axi_ethernet_lite_cursor_advance(cursor));

	xilinx_axi_ethernet_lite_write_reg(config, length_addr, net_pkt_get_len(pkt));

	/* as API is asynchronous, need not wait for TX completion */
	xilinx_axi_ethernet_lite_write_reg(config, control_addr,
					   XILINX_AXI_ETHERNET_LITE_TX_PING_TX_MASK);

#if defined(CONFIG_NET_L2_PTP)
	if(wait_ptp){
		int ret = skadi_sem_take(&data->tx_tstamp_available, K_FOREVER);

		/* should not fail with K_FOREVER */
		__ASSERT(!ret, "Could not wait for semaphore!");

		if(data->tx_timestamp_status != 0){
			for(int i = 0; i < AXI_ETH_LITE_TX_MAX_TSTAMP_TRIES; i++){
				/* second change - might have failed due to a race condition / delay between AXI Eth confirming TX and TX actually going out */
				struct ha1588_tsu_timestamp tx_timestamp;

				ret = skadi_ptp_tsu_ha1588_get_tx_tstamp(config->ptp_clock, &tx_timestamp);

				data->tx_timestamp_status = ret;

				if(!ret){
					memcpy(&data->tx_timestamp, &tx_timestamp.tm, sizeof(data->tx_timestamp));
					break;
				}
				skadi_msleep(1);
			}
		}

		if(data->tx_timestamp_status == 0){
			memcpy(&pkt->timestamp, &data->tx_timestamp, sizeof(pkt->timestamp));
			skadi_net_if_add_tx_timestamp(pkt);
			ret = data->tx_timestamp_status;
		}
		else{
			LOG_ERR("TX timestamping failed: %d", data->tx_timestamp_status);
		}
		return ret;
	}
#endif

	return 0;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axi_eth_lite_send)

static inline int
xilinx_axi_ethernet_lite_read_to_pkt(const struct xilinx_axi_ethernet_lite_config *config,
				     struct net_pkt *pkt, mem_addr_t buffer_addr,
				     size_t bytes_to_read)
{
	int ret = 0;

	for (size_t read_bytes = 0; read_bytes < bytes_to_read; read_bytes += sizeof(uint32_t)) {
		uint32_t current_data = xilinx_axi_ethernet_lite_read_reg(config, buffer_addr);
		size_t bytes_to_write_now = read_bytes + sizeof(uint32_t) > bytes_to_read
						    ? bytes_to_read - read_bytes
						    : sizeof(uint32_t);

		ret += skadi_net_pkt_write_inline(pkt, &current_data, bytes_to_write_now);

		if (ret < 0) {
			LOG_ERR("Write error bytes %zu/%zu (%zu)", read_bytes, bytes_to_read,
				bytes_to_write_now);
		} else {
			LOG_DBG("Write OK bytes %zu/%zu (%zu) cursor %p remaining %d", read_bytes,
				bytes_to_read, bytes_to_write_now, pkt->cursor.buf,
				pkt->cursor.buf ? pkt->cursor.buf->size - pkt->cursor.buf->len : 0);
		}

		buffer_addr += sizeof(uint32_t);
	}
	return ret;
}

/* FIXME are there generic defines? */
#define XILINX_AXI_ETHERNET_LITE_ARP_PACKET_LENGTH 28

#define HEADER_BUF_SIZE                                                                            \
	(sizeof(struct net_eth_hdr) + MAX(sizeof(struct net_ipv4_hdr), sizeof(struct net_ipv6_hdr)))
#define HEADER_BUF_SIZE_ALIGNED                                                                    \
	((HEADER_BUF_SIZE) + sizeof(uint32_t) - (HEADER_BUF_SIZE) % sizeof(uint32_t))

static inline bool axi_eth_lite_read_reg_is_busy(const struct xilinx_axi_ethernet_lite_config *config, mem_addr_t status_addr){
	return (xilinx_axi_ethernet_lite_read_reg(config, status_addr) & XILINX_AXI_ETHERNET_LITE_RX_CTRL_READY_ENABLE_MASK) != 0;
}

static inline void
xilinx_axi_ethernet_lite_receive_if_possible(const struct xilinx_axi_ethernet_lite_config *config,
					     struct xilinx_axi_ethernet_lite_data *data,
					     mem_addr_t buffer_addr, mem_addr_t status_addr)
{
	size_t packet_size = NET_ETH_MTU;
	uint8_t header_buf[HEADER_BUF_SIZE_ALIGNED];
	uint16_t len;

	struct net_pkt *pkt;
	const struct net_eth_hdr *hdr;

	if (!axi_eth_lite_read_reg_is_busy(config, status_addr)) {
		/* no data*/
		return;
	}

	for (size_t read_bytes = 0; read_bytes < sizeof(header_buf);
	     read_bytes += sizeof(uint32_t)) {
		uint32_t current_data = xilinx_axi_ethernet_lite_read_reg(config, buffer_addr);

		memcpy(&header_buf[read_bytes], &current_data, sizeof(current_data));
		buffer_addr += sizeof(uint32_t);
	}

	hdr = (struct net_eth_hdr *)header_buf;
	len = hdr->type;
	/*
	 * AXI Ethernet Lite cannot tell us the length of the received packet, so we try to parse it
	 * Also, FCS is not used by Zephyr stack
	 */
	switch (ntohs(len)) {
	case NET_ETH_PTYPE_ARP:
		/* fixed length */
		packet_size =
			sizeof(struct net_eth_hdr) + XILINX_AXI_ETHERNET_LITE_ARP_PACKET_LENGTH;
		break;
	case NET_ETH_PTYPE_IP: {
		const struct net_ipv4_hdr *ip4_hdr =
			(const struct net_ipv4_hdr *)&header_buf[sizeof(*hdr)];
		len = ip4_hdr->len;
		packet_size = ntohs(len);
		/* length includes ipv4 header length */
		packet_size += sizeof(struct net_eth_hdr);
		break;
	}
	case NET_ETH_PTYPE_IPV6: {
		const struct net_ipv6_hdr *ip6_hdr =
			(const struct net_ipv6_hdr *)&header_buf[sizeof(*hdr)];
		/* payload + any optional extension headers */
		len = ip6_hdr->len;
		packet_size = ntohs(len);
		packet_size += sizeof(struct net_eth_hdr) + sizeof(*ip6_hdr);
		break;
	}
	default:
		/* use the full MTU... */
		break;
	}

	pkt = skadi_net_pkt_rx_alloc_with_buffer(data->interface, packet_size, AF_UNSPEC, 0, K_NO_WAIT);

	if (!pkt) {
		LOG_WRN("Could not alloc RX packet!");
		goto out;
	}

	skadi_net_pkt_write_inline(pkt, header_buf, MIN(sizeof(header_buf), packet_size));

	LOG_DBG("Pkt allocated with size %zu written %zu", packet_size,
		MIN(sizeof(header_buf), packet_size));

	if (packet_size > HEADER_BUF_SIZE_ALIGNED &&
		xilinx_axi_ethernet_lite_read_to_pkt(config, pkt, buffer_addr,
						     packet_size - HEADER_BUF_SIZE_ALIGNED)) {
			/* this should never happen, ignore it if it does but warn */
			LOG_ERR("Could not read data to packet!");
	}
#if defined(CONFIG_NET_L2_PTP)
	/* invalid by default */
	pkt->timestamp.nanosecond = UINT32_MAX;
	pkt->timestamp.second = UINT64_MAX;

	if(skadi_ptp_tsu_ha1588_packet_matches_rx_filter(pkt) || IS_ENABLED(CONFIG_HA155_TIMESTAMP_ALL_RX)){
		int ret;
#ifdef CONFIG_PTP_CLOCK_HA1588
		if(config->have_ha1588_tsu && data->ha1588_was_reset){
			/* can use precise timestamp from ha1588 */
			struct ha1588_tsu_timestamp rx_timestamp;

			ret = skadi_ptp_tsu_ha1588_get_rx_tstamp(config->ptp_clock, &rx_timestamp);

			memcpy(&pkt->timestamp, &rx_timestamp, sizeof(pkt->timestamp));
		}
		else{
#endif /* CONFIG_PTP_CLOCK_HA1588 */
		/* must use software timestamp */
		ret = skadi_ptp_clock_get(config->ptp_clock, &pkt->timestamp);
#ifdef CONFIG_PTP_CLOCK_HA1588
		}
#endif /* CONFIG_PTP_CLOCK_HA1588 */

		if(data->ha1588_was_reset && ret){
			LOG_ERR("Failed to get RX timestamp for packet!");
			// obvious error value
			memset(&pkt->timestamp, 0xff, sizeof(pkt->timestamp));
		}
	}
#endif

	if (skadi_net_recv_data(data->interface, pkt) < 0) {
		LOG_ERR("Could not receive data!");
		skadi_net_pkt_unref(pkt);
	}

out:
	/* re-sets status bit - buffer may be used again */
	xilinx_axi_ethernet_lite_write_reg(
		config, status_addr,
		status_addr == XILINX_AXI_ETHERNET_LITE_RX_PING_CTRL_REG_OFFSET
			? XILINX_AXI_ETHERNET_LITE_RX_CTRL_IRQ_ENABLE_MASK
			: 0);
}


#ifdef CONFIG_NET_L2_PTP

static inline void axi_eth_lite_process_tx_timestamp(const struct device *dev){
	struct xilinx_axi_ethernet_lite_data *data = dev->data;
	const struct xilinx_axi_ethernet_lite_config *config = dev->config;
	int ret;

#ifdef CONFIG_PTP_CLOCK_HA1588
	if(config->have_ha1588_tsu){
		/* can use precise timestamp from ha1588 */
		struct ha1588_tsu_timestamp tx_timestamp;

		/* AT LEAST one timestamp must work - then tx_timestamp is valid */
		ret = skadi_ptp_tsu_ha1588_get_tx_tstamp(config->ptp_clock, &tx_timestamp);
		
		/* cannot have multiple packets in flight - always make sure we are using the last timestamp! */
		while(skadi_ptp_tsu_ha1588_get_tx_tstamp(config->ptp_clock, &tx_timestamp) == 0);

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

#else

static inline void axi_eth_lite_process_tx_timestamp(const struct device *dev){
	ARG_UNUSED(dev);
}

#endif

/* the interrupt on this device is a bit limited: it cannot tell us which event triggered the IRQ */
static void xilinx_axi_ethernet_lite_isr(const struct device *dev)
{
	int tx_opportunities = 0;
	struct xilinx_axi_ethernet_lite_data *data = dev->data;
	const struct xilinx_axi_ethernet_lite_config *config = dev->config;
#ifdef CONFIG_PTP_CLOCK_HA1588
	struct ha1588_tsu_timestamp rx_timestamp;
#endif

	/* might have been TX completion... */
	if ((xilinx_axi_ethernet_lite_read_reg(config,
					       XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_REG_OFFSET) &
	     XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_BUSY_MASK) == 0) {
		tx_opportunities++;
	}
	if (config->has_tx_ping_pong &&
	    (xilinx_axi_ethernet_lite_read_reg(config,
					       XILINX_AXI_ETHERNET_LITE_TX_PONG_CTRL_REG_OFFSET) &
	     XILINX_AXI_ETHERNET_LITE_TX_PING_CTRL_BUSY_MASK) == 0) {
		tx_opportunities++;
	}
	while (skadi_sem_count_get(&data->tx_sem) < tx_opportunities) {
		skadi_sem_give(&data->tx_sem);
		axi_eth_lite_process_tx_timestamp(dev);
	}
	/* no overflow */
	__ASSERT_NO_MSG(skadi_sem_count_get(&data->tx_sem) == tx_opportunities);

	/* need to use the toggle to receive packets in correct sequence */
	if (config->has_rx_ping_pong && data->rx_ping_toggle) {
		xilinx_axi_ethernet_lite_receive_if_possible(
			config, data, XILINX_AXI_ETHERNET_LITE_RX_PONG_START_REG_OFFSET,
			XILINX_AXI_ETHERNET_LITE_RX_PONG_CTRL_REG_OFFSET);
        xilinx_axi_ethernet_lite_receive_if_possible(
			config, data, XILINX_AXI_ETHERNET_LITE_RX_PING_START_REG_OFFSET,
			XILINX_AXI_ETHERNET_LITE_RX_PING_CTRL_REG_OFFSET);
	} else {
		xilinx_axi_ethernet_lite_receive_if_possible(
			config, data, XILINX_AXI_ETHERNET_LITE_RX_PING_START_REG_OFFSET,
			XILINX_AXI_ETHERNET_LITE_RX_PING_CTRL_REG_OFFSET);
        xilinx_axi_ethernet_lite_receive_if_possible(
			config, data, XILINX_AXI_ETHERNET_LITE_RX_PONG_START_REG_OFFSET,
			XILINX_AXI_ETHERNET_LITE_RX_PONG_CTRL_REG_OFFSET);
	}
	data->rx_ping_toggle = !data->rx_ping_toggle;

#ifdef CONFIG_NET_L2_PTP
	if(config->have_ha1588_tsu && data->ha1588_was_reset)
	{
		// TODO consume RX timestamps for packets that were discarded due to lack of buffer space
		// stop iterating as soon as one of the registers goes busy
		while(!axi_eth_lite_read_reg_is_busy(config, XILINX_AXI_ETHERNET_LITE_RX_PONG_CTRL_REG_OFFSET) && !axi_eth_lite_read_reg_is_busy(config, XILINX_AXI_ETHERNET_LITE_RX_PING_CTRL_REG_OFFSET)){
			if(skadi_ptp_tsu_ha1588_get_rx_tstamp(config->ptp_clock, &rx_timestamp) != 0){
				break;
			}
		}
	}
#endif
}
SKADI_GENERATE_IRQ_HANDLER_WRAPPER(xilinx_axi_ethernet_lite_isr)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, xilinx_axi_ethernet_lite_timer_fn, struct k_timer *timer)
{
	const struct device *dev = timer->user_data;
	struct xilinx_axi_ethernet_lite_data *data = dev->data;
    const struct xilinx_axi_ethernet_lite_config *config = dev->config;

	/* concurrent invocation of ISR would be a problem */
	k_spinlock_key_t key = k_spin_lock(&data->timer_lock);

    skadi_irq_disable(config->irq_number);

	xilinx_axi_ethernet_lite_isr(dev);

    skadi_irq_enable(config->irq_number, SKADI_IRQ_PRIORITY_DEFAULT);

	k_spin_unlock(&data->timer_lock, key);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axi_ethernet_lite_timer_fn)

/* Xilinx OUI (Organizationally Unique Identifier) for MAC */
#define XILINX_OUI_BYTE_0 0x00
#define XILINX_OUI_BYTE_1 0x0A
#define XILINX_OUI_BYTE_2 0x35

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, xilinx_axi_eth_lite_probe, const struct device *orig_dev)
{
    const struct device *dev = skadi_get_own_device_representation(orig_dev);
	const struct xilinx_axi_ethernet_lite_config *config = dev->config;
	struct xilinx_axi_ethernet_lite_data *data = dev->data;

	config->config_func(data);

	if (config->has_random_mac_address) {
		gen_random_mac(data->mac_addr, XILINX_OUI_BYTE_0, XILINX_OUI_BYTE_1,
			       XILINX_OUI_BYTE_2);
	}

	if (config->has_interrupt) {
		xilinx_axi_ethernet_lite_write_reg(config, XILINX_AXI_ETHERNET_LITE_GIE_REG_OFFSET,
						   XILINX_AXI_ETHERNET_LITE_GIE_ENABLE_MASK);
		/* start with 1 for ping-pong, as we can always start 2 transactions concurrently */
		if (skadi_sem_init(&data->tx_sem, config->has_tx_ping_pong ? 1 : 0, config->has_tx_ping_pong ? 2 : 1)) {
			LOG_ERR("Could not initialize semaphore!");
			return -EINVAL;
		}
	} else {
		LOG_INF("No interrupt configured - AXI Ethernet Lite will have to spin!");
	}
	if (CONFIG_ETH_XILINX_AXI_ETHERNET_LITE_TIMER_PERIOD) {
		skadi_timer_init(&data->rx_timer, SKADI_SUBSYSTEM_FUNCTION_POINTER(xilinx_axi_ethernet_lite_timer_fn), NULL);
		data->rx_timer.user_data = (void *)(uintptr_t)dev;
	}
#if defined(CONFIG_NET_L2_PTP)
	skadi_sem_init(&data->tx_tstamp_available, 0, 1);
#endif

	return 0;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(xilinx_axi_eth_lite_probe)

#define SETUP_IRQS(inst)                                                                           \
	LOG_INF("Registering interrupt handler!");	\
	if(skadi_register_interrupt_handler(DT_INST_IRQN(inst), NULL, SKADI_IRQ_HANDLER_FUNCTION_POINTER(inst,xilinx_axi_ethernet_lite_isr)) == false){	\
		LOG_ERR("Could not register ISR handler!");																							\
	}																																		\
	LOG_INF("Registered interrupt handler - enabling interrupt!");	\
	skadi_irq_enable(DT_INST_IRQN(inst), SKADI_IRQ_PRIORITY_DEFAULT);

#if defined(CONFIG_NET_L2_PTP)
#define SETUP_PTP_CLOCKS(inst) 																	\
 .ptp_clock = DEVICE_DT_GET(DT_CLOCKS_CTLR(DT_DRV_INST(inst))),									\
 .have_ha1588_tsu = DT_PROP_OR(DT_CLOCKS_CTLR(DT_DRV_INST(inst)), ha1588_tsu, false)
#else
#define SETUP_PTP_CLOCKS(inst)
#endif

#define XILINX_AXI_ETHERNET_LITE_INIT(inst)                                                        \
                                                                                                   \
	static void xilinx_axi_ethernet_lite_config_##inst(                                        \
		struct xilinx_axi_ethernet_lite_data *dev)                                         \
	{                                                                                          \
		COND_CODE_1(DT_INST_NODE_HAS_PROP(inst, interrupts), (SETUP_IRQS(inst)),        \
			    (LOG_INF("No IRQs defined!")));        \
	}                                                                                          \
                                                                                                   \
	static struct xilinx_axi_ethernet_lite_data data_##inst = {                                \
		.mac_addr = DT_INST_PROP_OR(inst, local_mac_address, {0}),                         \
	};                                                                                         \
	static const struct xilinx_axi_ethernet_lite_config config_##inst = {                      \
		.config_func = xilinx_axi_ethernet_lite_config_##inst,                             \
		.phy = DEVICE_DT_GET_OR_NULL(DT_INST_PHANDLE(inst, phy_handle)),                   \
		.reg = DT_REG_ADDR(DT_INST_PARENT(inst)),                                          \
		.has_rx_ping_pong = DT_INST_PROP(inst, xlnx_rx_ping_pong),                         \
		.has_tx_ping_pong = DT_INST_PROP(inst, xlnx_tx_ping_pong) && !IS_ENABLED(CONFIG_NET_L2_PTP), \
		.has_random_mac_address = DT_INST_PROP(inst, zephyr_random_mac_address),           \
		.has_interrupt = DT_INST_NODE_HAS_PROP(inst, interrupts),                           \
        .irq_number = DT_INST_IRQN(inst),													\
		SETUP_PTP_CLOCKS(inst)                         									\
    };                         \
                                                                                           	   \
	DEVICE_DT_INST_DEFINE(inst, NULL, NULL, &data_##inst,          	   \
				      &config_##inst, PRE_KERNEL_1, CONFIG_ETH_INIT_PRIORITY,	   \
				      NULL);

DT_INST_FOREACH_STATUS_OKAY(XILINX_AXI_ETHERNET_LITE_INIT);

SKADI_GENERATE_DEVICE_REPRESENTATION_WRAPPER;
