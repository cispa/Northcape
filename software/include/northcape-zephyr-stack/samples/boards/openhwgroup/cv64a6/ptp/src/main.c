/*
 * Copyright (c) 2024 BayLibre SAS
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(net_ptp_sample, LOG_LEVEL_DBG);

#include <zephyr/kernel.h>

#include <errno.h>
#include <stdlib.h>

#include "ptp/clock.h"
#include "ptp/port.h"

#include <zephyr/net/gptp.h>
#include "ethernet/gptp/gptp_messages.h"
#include "ethernet/gptp/gptp_data_set.h"


#include <unistd.h>
#include <math.h>

#include <cv64a6.h>

#include <zephyr/skadi/skadi_benchmark.h>

#ifdef CONFIG_PTP
static int get_current_status(void)
{
	struct ptp_port *port;
	sys_slist_t *ports_list = ptp_clock_ports_list();

	if (!ports_list || sys_slist_len(ports_list) == 0) {
		return -EINVAL;
	}

	port = CONTAINER_OF(sys_slist_peek_head(ports_list), struct ptp_port, node);

	if (!port) {
		return -EINVAL;
	}

	switch (ptp_port_state(port)) {
	case PTP_PS_INITIALIZING:
	case PTP_PS_FAULTY:
	case PTP_PS_DISABLED:
	case PTP_PS_LISTENING:
	case PTP_PS_PRE_TIME_TRANSMITTER:
	case PTP_PS_PASSIVE:
	case PTP_PS_UNCALIBRATED:
		printk("FAIL\n");
		return 0;
	case PTP_PS_TIME_RECEIVER:
		printk("TIME RECEIVER\n");
		return 2;
	case PTP_PS_TIME_TRANSMITTER:
	case PTP_PS_GRAND_MASTER:
		printk("TIME TRANSMITTER\n");
		return 1;
	}

	return -1;
}

static int64_t get_current_timediff(void){
	const struct ptp_current_ds *dataset = ptp_clock_current_ds();
	return dataset -> offset_from_tt;
}

static int64_t get_current_prop_delay(void){
	const struct ptp_current_ds *dataset = ptp_clock_current_ds();
	return dataset -> mean_delay;
}

static bool is_synchronized(void){
	const struct ptp_current_ds *dataset = ptp_clock_current_ds();
	return dataset -> sync_uncertain;
}
#else
static int get_current_status(void)
{
	struct gptp_domain *domain;
	struct gptp_port_ds *port_ds;
	int ret, port;

	port = 1;

	domain = gptp_get_domain();

	ret = gptp_get_port_data(domain, port, &port_ds,
				 NULL, NULL, NULL, NULL);
	if (ret < 0) {
		LOG_WRN("Cannot get gPTP information for port %d (%d)",
			port, ret);
		return ret;
	}

	if (port != port_ds->port_id.port_number) {
		return -EINVAL;
	}

	switch (GPTP_GLOBAL_DS()->selected_role[port]) {
	case GPTP_PORT_INITIALIZING:
	case GPTP_PORT_FAULTY:
	case GPTP_PORT_DISABLED:
	case GPTP_PORT_LISTENING:
	case GPTP_PORT_PRE_MASTER:
	case GPTP_PORT_PASSIVE:
	case GPTP_PORT_UNCALIBRATED:
		printk("FAIL\n");
		return 0;
	case GPTP_PORT_MASTER:
		printk("MASTER\n");
		return 1;
	case GPTP_PORT_SLAVE:
		printk("SLAVE\n");
		return 2;
	}

	return -1;
}

static int64_t get_current_timediff(void){
	struct gptp_domain *domain;

	domain = gptp_get_domain();

	return domain->global_ds.clk_src_phase_offset.low;
}

static int64_t get_current_prop_delay(void){
	struct gptp_domain *domain;
	struct gptp_port_ds *port_ds;
	int ret, port;

	port = 1;

	domain = gptp_get_domain();

	ret = gptp_get_port_data(domain, port, &port_ds,
		NULL, NULL, NULL, NULL);

	return port_ds->neighbor_prop_delay;
}

static bool is_synchronized(void){
	return 0;
}

#endif

typedef void (*gptp_prop_callback_t)(int64_t);

extern void gptp_set_prop_callback(gptp_prop_callback_t new_prop_callback);

typedef void (*gptp_sync_tx_callback_t)(const struct net_ptp_time *tx_time);

extern void gptp_register_sync_tx_callback(gptp_sync_tx_callback_t gptp_sync_tx_callback);

#define WAIT_SAMPLES 30
#define COLLECT_SAMPLES 250

static size_t delays_to_wait, collected_delays, discarded_delays;
static size_t sync_tx_to_wait, collected_sync_tx, discarded_sync_tx;

static int64_t prop_delays[COLLECT_SAMPLES];
static int64_t sync_tx_samples[COLLECT_SAMPLES];
static uint64_t last_sync_tx;

static bool propagation_delays_complete, sync_complete;




static void gptp_prop_callback(int64_t prop_time){

	if(delays_to_wait){
		delays_to_wait--;
		return;
	}

	if(prop_time <= 0){
		discarded_delays++;
		return;
	}

	if(collected_delays == COLLECT_SAMPLES){
		propagation_delays_complete = true;
		skadi_benchmark_evaluate_samples_real(prop_delays, COLLECT_SAMPLES, discarded_delays, "Propagation delays", "samples");
		collected_delays = 0;
		discarded_delays = 0;

		if(propagation_delays_complete && sync_complete){
			z_cv64a6_finish_test(0);
		}
	}

	prop_delays[collected_delays++] = prop_time;
}

static void gptp_sync_tx_callback(const struct net_ptp_time *tx_time){
	uint64_t tx_time_ns = tx_time -> second;

	tx_time_ns *= NSEC_PER_SEC;
	tx_time_ns += tx_time->nanosecond;

	if(sync_tx_to_wait){
		sync_tx_to_wait--;
		last_sync_tx = tx_time_ns;
		return;
	}

	if(collected_sync_tx == COLLECT_SAMPLES){
		sync_complete = true;
		skadi_benchmark_evaluate_samples_real(sync_tx_samples, COLLECT_SAMPLES, 0, "Sync TX times", "samples");
		collected_sync_tx = 0;
		discarded_sync_tx = 0;

		if(propagation_delays_complete && sync_complete){
			z_cv64a6_finish_test(0);
		}
	}
	/* we are interested in the INTERVAL */
	sync_tx_samples[collected_sync_tx++] = tx_time_ns - last_sync_tx;

	last_sync_tx = tx_time_ns;
}

void init_testing(void)
{
	uint32_t uptime = k_uptime_get_32();
	int ret;

	delays_to_wait = WAIT_SAMPLES;
	collected_delays = 0;
	discarded_delays = 0;

	propagation_delays_complete = sync_complete = false;

	gptp_set_prop_callback(gptp_prop_callback);

	sync_tx_to_wait = WAIT_SAMPLES;
	collected_sync_tx = 0;
	discarded_sync_tx = 0;

	gptp_register_sync_tx_callback(gptp_sync_tx_callback);

	while(true){
		uint32_t current_time;

		k_msleep(1000);
		
		current_time = k_uptime_get_32() - uptime;

		/* Try to figure out what is the sync state.
		* Return:
		*  <0 - configuration error
		*   0 - not time sync
		*   1 - we are TimeTransmitter
		*   2 - we are TimeReceiver
		*/
		ret = get_current_status();

		if(ret < 0){
			LOG_ERR("Synchronization error %d at time %"PRIu32, -ret, current_time);
			continue;
		}

		if(ret == 0){
			LOG_WRN("Waiting for time synchronization at time %"PRIu32, current_time);
			continue;
		}

		/* only makes sense to track as a slave */
		if(ret == 1){
			gptp_set_prop_callback(NULL);
			propagation_delays_complete = true;
		}

		LOG_INF("Sync state: offset from transmitter %"PRId64" propagation delay %"PRId64" %s",
			get_current_timediff(), get_current_prop_delay(),
			is_synchronized() ? "synchronized" : "not synchronized");
	}
}

int main(void)
{
	init_testing();
	return 0;
}
