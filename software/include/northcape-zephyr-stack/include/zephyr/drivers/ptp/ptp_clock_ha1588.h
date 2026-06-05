/*
 *  gGmbH
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef ZEPHYR_INCLUDE_DRIVERS_PTP_PTP_CLOCK_HA1588_H__
#define ZEPHYR_INCLUDE_DRIVERS_PTP_PTP_CLOCK_HA1588_H__
#include <zephyr/net/ptp_time.h>


/**
 * Timestamp-related metadata for ha1588
 */
struct ha1588_tsu_timestamp {
    /** timestamp value in PTP format */
    struct net_ptp_time tm;
    /** sequence ID of PTP message the timestamp belongs to */
    uint16_t ptp_seqid;
    /** checksum of PTP message the timestamp belongs to */
    uint16_t ptp_checksum;
    /** message ID of PTP message the timestamp belongs to */
    uint8_t ptp_msgid;
};

/**
 * @brief Get oldest RX timestamp and associated metadata from ha1588 FIFO.
 * @param dev ha1588 device
 * @param tstamp timestamp and metadata
 * @retval 0 timestamp and metadata loaded successfully
 * @retval -EIO FIFO is empty
 */
extern int ptp_tsu_ha1588_get_rx_tstamp(const struct device *dev, 
    struct ha1588_tsu_timestamp *tstamp);

/**
 * @brief Get oldest TX timestamp and associated metadata from ha1588 FIFO.
 * @param dev ha1588 device
 * @param tstamp timestamp and metadata
 * @retval 0 timestamp and metadata loaded successfully
 * @retval -EIO FIFO is empty
 */
extern int ptp_tsu_ha1588_get_tx_tstamp(const struct device *dev, 
		struct ha1588_tsu_timestamp *tstamp);

/**
 * @brief Select whether to disable all incoming packets instead only PTP packets (default: off).
 * @param dev ha1588 device
 * @param enable true for all packets, false for ptp only
 * @retval 0 set successfully
 * @retval -EOPNOTSUPP not supported on this ha1588
 */
extern int ptp_tsu_ha1588_set_timestamp_all_rx(const struct device *dev,
        bool enable);

/**
 * @brief Select whether to disable all outgoing packets instead only PTP packets (default: off).
 * @param dev ha1588 device
 * @param enable true for all packets, false for ptp only
 * @retval 0 set successfully
 * @retval -EOPNOTSUPP not supported on this ha1588
 */
extern int ptp_tsu_ha1588_set_timestamp_all_tx(const struct device *dev,
    bool enable);

/**
 * @brief Reset ha1588' TSUs. This needs to be done *after* the link has gone up, i.e., clocks have stabilized.
 */
extern void ptp_tsu_ha1588_reset(const struct device *dev);

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
extern bool ptp_tsu_ha1588_packet_matches_rx_filter(struct net_pkt *pkt);

#endif /* ZEPHYR_INCLUDE_DRIVERS_PTP_PTP_CLOCK_HA1588_H__ */
