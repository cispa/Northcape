/*
 *  gGmbH
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef ZEPHYR_INCLUDE_SKADI_SUBSYSTEMS_PTP_SKADI_PTP_CLOCK_HA1588_H__
#define ZEPHYR_INCLUDE_SKADI_SUBSYSTEMS_PTP_SKADI_PTP_CLOCK_HA1588_H__
#include <zephyr/net/ptp_time.h>

#include <zephyr/drivers/ptp/ptp_clock_ha1588.h>

#include <zephyr/skadi/skadi_subsystem.h>

/**
 * @brief Get oldest RX timestamp and associated metadata from ha1588 FIFO.
 * @param dev ha1588 device
 * @param tstamp timestamp and metadata
 * @retval 0 timestamp and metadata loaded successfully
 * @retval -EIO FIFO is empty
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_ptp_tsu_ha1588_get_rx_tstamp, const struct device *dev, struct ha1588_tsu_timestamp *tstamp);

static inline int skadi_ptp_tsu_ha1588_get_rx_tstamp(const struct device *dev, struct ha1588_tsu_timestamp *tstamp){
    struct ha1588_tsu_timestamp *tstamp_token = skadi_cap_ops_derive_arg_wo(tstamp, sizeof(*tstamp));
    int ret;

    __ASSERT_NO_MSG(tstamp_token);

    if(!tstamp_token){
        return -ENOMEM;
    }

    ret = __skadi_ptp_tsu_ha1588_get_rx_tstamp(dev, tstamp_token);

    (void)skadi_cap_ops_drop(tstamp_token);

    return ret;
}

/**
 * @brief Get oldest TX timestamp and associated metadata from ha1588 FIFO.
 * @param dev ha1588 device
 * @param tstamp timestamp and metadata
 * @retval 0 timestamp and metadata loaded successfully
 * @retval -EIO FIFO is empty
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_ptp_tsu_ha1588_get_tx_tstamp, const struct device *dev, struct ha1588_tsu_timestamp *tstamp);

static inline int skadi_ptp_tsu_ha1588_get_tx_tstamp(const struct device *dev, struct ha1588_tsu_timestamp *tstamp){
    struct ha1588_tsu_timestamp *tstamp_token = skadi_cap_ops_derive_arg_wo(tstamp, sizeof(*tstamp));
    int ret;

    __ASSERT_NO_MSG(tstamp_token);

    if(!tstamp_token){
        return -ENOMEM;
    }

    ret = __skadi_ptp_tsu_ha1588_get_tx_tstamp(dev, tstamp_token);

    (void)skadi_cap_ops_drop(tstamp_token);

    return ret;
}

/**
 * @brief Select whether to disable all incoming packets instead only PTP packets (default: off).
 * @param dev ha1588 device
 * @param enable true for all packets, false for ptp only
 * @retval 0 set successfully
 * @retval -EOPNOTSUPP not supported on this ha1588
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_ptp_tsu_ha1588_set_timestamp_all_rx, const struct device *dev, bool enable);

#define skadi_ptp_tsu_ha1588_set_timestamp_all_rx(DEV, ENABLE) __skadi_ptp_tsu_ha1588_set_timestamp_all_rx(DEV, ENABLE)

/**
 * @brief Select whether to disable all outgoing packets instead only PTP packets (default: off).
 * @param dev ha1588 device
 * @param enable true for all packets, false for ptp only
 * @retval 0 set successfully
 * @retval -EOPNOTSUPP not supported on this ha1588
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_ptp_tsu_ha1588_set_timestamp_all_tx, const struct device *dev, bool enable);

#define skadi_ptp_tsu_ha1588_set_timestamp_all_tx(DEV, ENABLE) __skadi_ptp_tsu_ha1588_set_timestamp_all_tx(DEV, ENABLE)

/**
 * @brief Reset ha1588' TSUs. This needs to be done *after* the link has gone up, i.e., clocks have stabilized.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void, __skadi_ptp_tsu_ha1588_reset, const struct device *dev);

#define skadi_ptp_tsu_ha1588_reset(DEV) __skadi_ptp_tsu_ha1588_reset(DEV)

/**
 * @brief Check whether a received packet triggered ha1588's RX filter.
 * If it did, the ethernet driver needs to retrieve the packet's timestamp from the 
 * TSU's FIFO in order to prevent overflow.
 * The ha1588 TSU triggers on L2 PTP packets (optionally over VLAN),
 * MPLS PTP packets and L4 PTP packets over IPv4 or IPv6.
 * 
 * @param pkt network packet starting with Ethernet header. Will not modify metadata.
 * @retval true packet matches the filter
 * @retval false packet does not match the filter
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, __skadi_ptp_tsu_ha1588_packet_matches_rx_filter, struct net_pkt *pkt);

#define skadi_ptp_tsu_ha1588_packet_matches_rx_filter(PKT) __skadi_ptp_tsu_ha1588_packet_matches_rx_filter(pkt)

#endif /* ZEPHYR_INCLUDE_SKADI_SUBSYSTEMS_PTP_SKADI_PTP_CLOCK_HA1588_H__ */
