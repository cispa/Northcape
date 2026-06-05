/*
 * Copyright (c) 2018 Intel Corporation.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/skadi/skadi_queue.h>
#include <zephyr/skadi/skadi_sched.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(net_tc, CONFIG_NET_TC_LOG_LEVEL);

#include <zephyr/kernel.h>
#include <string.h>

#include <zephyr/net/net_core.h>
#include <zephyr/net/net_pkt.h>
#include <zephyr/net/net_stats.h>

#include "net_private.h"
#include "net_stats.h"
#include "net_tc_mapping.h"
/* Template for thread name. The "xx" is either "TX" denoting transmit thread,
 * or "RX" denoting receive thread. The "q[y]" denotes the traffic class queue
 * where y indicates the traffic class id. The value of y can be from 0 to 7.
 */
#define MAX_NAME_LEN sizeof("xx_q[y]")

#if NET_TC_TX_COUNT > 0
static struct net_traffic_class tx_classes[NET_TC_TX_COUNT];
#endif

#if NET_TC_RX_COUNT > 0
static struct net_traffic_class rx_classes[NET_TC_RX_COUNT];
#endif

#if NET_TC_RX_COUNT > 0 || NET_TC_TX_COUNT > 0
static void submit_to_queue(struct k_fifo *queue, struct net_pkt *pkt)
{
	skadi_fifo_put(queue, pkt);
}
#endif

bool net_tc_submit_to_tx_queue(uint8_t tc, struct net_pkt *pkt)
{
#if NET_TC_TX_COUNT > 0
	net_pkt_set_tx_stats_tick(pkt, skadi_cycle_get_32());

	submit_to_queue(tx_classes[tc].fifo, pkt);
#else
	ARG_UNUSED(tc);
	ARG_UNUSED(pkt);
#endif
	return true;
}

void net_tc_submit_to_rx_queue(uint8_t tc, struct net_pkt *pkt)
{
#if NET_TC_RX_COUNT > 0
	net_pkt_set_rx_stats_tick(pkt, skadi_cycle_get_32());

	submit_to_queue(rx_classes[tc].fifo, pkt);
#else
	ARG_UNUSED(tc);
	ARG_UNUSED(pkt);
#endif
}

int net_tx_priority2tc(enum net_priority prio)
{
#if NET_TC_TX_COUNT > 0
	if (prio > NET_PRIORITY_NC) {
		/* Use default value suggested in 802.1Q */
		prio = NET_PRIORITY_BE;
	}

	return tx_prio2tc_map[prio];
#else
	ARG_UNUSED(prio);

	return 0;
#endif
}

int net_rx_priority2tc(enum net_priority prio)
{
#if NET_TC_RX_COUNT > 0
	if (prio > NET_PRIORITY_NC) {
		/* Use default value suggested in 802.1Q */
		prio = NET_PRIORITY_BE;
	}

	return rx_prio2tc_map[prio];
#else
	ARG_UNUSED(prio);

	return 0;
#endif
}

#if defined(CONFIG_NET_TC_THREAD_PRIO_CUSTOM)
#define BASE_PRIO_TX CONFIG_NET_TC_TX_THREAD_BASE_PRIO
#elif defined(CONFIG_NET_TC_THREAD_COOPERATIVE)
#define BASE_PRIO_TX (CONFIG_NET_TC_NUM_PRIORITIES - 1)
#else
#define BASE_PRIO_TX (CONFIG_NET_TC_TX_COUNT - 1)
#endif

#define PRIO_TX(i, _) (BASE_PRIO_TX - i)

#if defined(CONFIG_NET_TC_THREAD_PRIO_CUSTOM)
#define BASE_PRIO_RX CONFIG_NET_TC_RX_THREAD_BASE_PRIO
#elif defined(CONFIG_NET_TC_THREAD_COOPERATIVE)
#define BASE_PRIO_RX (CONFIG_NET_TC_NUM_PRIORITIES - 1)
#else
#define BASE_PRIO_RX (CONFIG_NET_TC_RX_COUNT - 1)
#endif

#define PRIO_RX(i, _) (BASE_PRIO_RX - i)

#if NET_TC_TX_COUNT > 0
/* Convert traffic class to thread priority */
static uint8_t tx_tc2thread(uint8_t tc)
{
	/* Initial implementation just maps the traffic class to certain queue.
	 * If there are less queues than classes, then map them into
	 * some specific queue.
	 *
	 * Lower value in this table means higher thread priority. The
	 * value is used as a parameter to K_PRIO_COOP() or K_PRIO_PREEMPT()
	 * which converts it to actual thread priority.
	 *
	 * Higher traffic class value means higher priority queue. This means
	 * that thread_priorities[7] value should contain the highest priority
	 * for the TX queue handling thread.
	 *
	 * For example, if NET_TC_TX_COUNT = 8, which is the maximum number of
	 * traffic classes, then this priority array will contain following
	 * values if preemptive priorities are used:
	 *      7, 6, 5, 4, 3, 2, 1, 0
	 * and
	 *      14, 13, 12, 11, 10, 9, 8, 7
	 * if cooperative priorities are used.
	 *
	 * Then these will be converted to following thread priorities if
	 * CONFIG_NET_TC_THREAD_COOPERATIVE is enabled:
	 *      -1, -2, -3, -4, -5, -6, -7, -8
	 *
	 * and if CONFIG_NET_TC_THREAD_PREEMPTIVE is enabled, following thread
	 * priorities are used:
	 *       7, 6, 5, 4, 3, 2, 1, 0
	 *
	 * This means that the lowest traffic class 1, will have the lowest
	 * cooperative priority -1 for coop priorities and 7 for preemptive
	 * priority.
	 */
	static const uint8_t thread_priorities[] = {
		LISTIFY(NET_TC_TX_COUNT, PRIO_TX, (,))
	};

	BUILD_ASSERT(NET_TC_TX_COUNT <= CONFIG_NUM_COOP_PRIORITIES,
		     "Too many traffic classes");

	NET_ASSERT(tc < ARRAY_SIZE(thread_priorities));

	return thread_priorities[tc];
}
#endif

#if NET_TC_RX_COUNT > 0
/* Convert traffic class to thread priority */
static uint8_t rx_tc2thread(uint8_t tc)
{
	static const uint8_t thread_priorities[] = {
		LISTIFY(NET_TC_RX_COUNT, PRIO_RX, (,))
	};

	BUILD_ASSERT(NET_TC_RX_COUNT <= CONFIG_NUM_COOP_PRIORITIES,
		     "Too many traffic classes");

	NET_ASSERT(tc < ARRAY_SIZE(thread_priorities));

	return thread_priorities[tc];
}
#endif

#if defined(CONFIG_NET_STATISTICS)
/* Fixup the traffic class statistics so that "net stats" shell command will
 * print output correctly.
 */
#if NET_TC_TX_COUNT > 0
static void tc_tx_stats_priority_setup(struct net_if *iface)
{
	int i;

	for (i = 0; i < 8; i++) {
		net_stats_update_tc_sent_priority(iface, net_tx_priority2tc(i),
						  i);
	}
}
#endif

#if NET_TC_RX_COUNT > 0
static void tc_rx_stats_priority_setup(struct net_if *iface)
{
	int i;

	for (i = 0; i < 8; i++) {
		net_stats_update_tc_recv_priority(iface, net_rx_priority2tc(i),
						  i);
	}
}
#endif

#if NET_TC_TX_COUNT > 0
static void net_tc_tx_stats_priority_setup(struct net_if *iface,
					   void *user_data)
{
	ARG_UNUSED(user_data);

	tc_tx_stats_priority_setup(iface);
}
#endif

#if NET_TC_RX_COUNT > 0
static void net_tc_rx_stats_priority_setup(struct net_if *iface,
					   void *user_data)
{
	ARG_UNUSED(user_data);

	tc_rx_stats_priority_setup(iface);
}
#endif
#endif

#if NET_TC_RX_COUNT > 0
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, tc_rx_handler, void *p1, void *p2, void *p3)
{
	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	struct k_fifo *fifo = p1;
	struct net_pkt *pkt;

	__ASSERT_NO_MSG(fifo);

	while (1) {
		pkt = skadi_fifo_get(fifo, K_FOREVER);
		if (pkt == NULL) {
			continue;
		}

		net_process_rx_packet(pkt);
	}
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(tc_rx_handler)
#endif

#if NET_TC_TX_COUNT > 0
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, tc_tx_handler, void *p1, void *p2, void *p3)
{
	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	struct k_fifo *fifo = p1;
	struct net_pkt *pkt;

	__ASSERT_NO_MSG(fifo);

	while (1) {
		pkt = skadi_fifo_get(fifo, K_FOREVER);
		if (pkt == NULL) {
			continue;
		}

		net_process_tx_packet(pkt);
	}
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(tc_tx_handler)
#endif

/* Create a fifo for each traffic class we are using. All the network
 * traffic goes through these classes.
 */
void net_tc_tx_init(void)
{
#if NET_TC_TX_COUNT == 0
	NET_DBG("No %s thread created", "TX");
	return;
#else
	int i;
	struct skadi_thread_create_params params;

	BUILD_ASSERT(NET_TC_TX_COUNT >= 0);

#if defined(CONFIG_NET_STATISTICS)
	net_if_foreach(net_tc_tx_stats_priority_setup, NULL);
#endif

	for (i = 0; i < NET_TC_TX_COUNT; i++) {
		uint8_t thread_priority;
		int priority;
		k_tid_t tid;

		thread_priority = tx_tc2thread(i);

		priority = IS_ENABLED(CONFIG_NET_TC_THREAD_COOPERATIVE) ?
			K_PRIO_COOP(thread_priority) :
			K_PRIO_PREEMPT(thread_priority);

		tx_classes[i].fifo = skadi_allocator_alloc_rw(sizeof(*tx_classes[i].fifo));

		if(!tx_classes[i].fifo){
			LOG_ERR("Could not allocate FIFO!");
			return;
		}

		params.new_thread = tx_classes[i].handler = skadi_allocator_alloc_rw(sizeof(*tx_classes[i].handler));
		params.stack = skadi_allocator_alloc_rw(CONFIG_NET_TX_STACK_SIZE);
		params.stack_size = CONFIG_NET_TX_STACK_SIZE;
		params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(tc_tx_handler);
		params.p1 = tx_classes[i].fifo;
		params.prio = priority;
		params.options = 0;
		params.delay = K_FOREVER;

		NET_DBG("[%d] Starting TX handler %p stack size %d "
			"prio %d %s(%d)", i,
			tx_classes[i].handler,
			CONFIG_NET_TX_STACK_SIZE,
			thread_priority,
			IS_ENABLED(CONFIG_NET_TC_THREAD_COOPERATIVE) ?
							"coop" : "preempt",
			priority);

		skadi_fifo_init(tx_classes[i].fifo);

		tid = skadi_thread_create(&params);
		if (!tid) {
			NET_ERR("Cannot create TC handler thread %d", i);
			continue;
		}

		if (IS_ENABLED(CONFIG_THREAD_NAME)) {
			char name[MAX_NAME_LEN];

			snprintk(name, sizeof(name), "tx_q[%d]", i);
			skadi_thread_name_set(tid, name);
		}

		skadi_thread_start(tid);
	}
#endif
}

void net_tc_rx_init(void)
{
#if NET_TC_RX_COUNT == 0
	NET_DBG("No %s thread created", "RX");
	return;
#else
	int i;
	struct skadi_thread_create_params params;

	BUILD_ASSERT(NET_TC_RX_COUNT >= 0);

#if defined(CONFIG_NET_STATISTICS)
	net_if_foreach(net_tc_rx_stats_priority_setup, NULL);
#endif

	for (i = 0; i < NET_TC_RX_COUNT; i++) {
		uint8_t thread_priority;
		int priority;
		k_tid_t tid;

		thread_priority = rx_tc2thread(i);

		priority = IS_ENABLED(CONFIG_NET_TC_THREAD_COOPERATIVE) ?
			K_PRIO_COOP(thread_priority) :
			K_PRIO_PREEMPT(thread_priority);

		rx_classes[i].fifo = skadi_allocator_alloc_rw(sizeof(*rx_classes[i].fifo));

		if(!rx_classes[i].fifo){
			LOG_ERR("Could not allocate FIFO!");
			return;
		}

		params.new_thread = rx_classes[i].handler = skadi_allocator_alloc_rw(sizeof(*rx_classes[i].handler));
		params.stack = skadi_allocator_alloc_rw(CONFIG_NET_RX_STACK_SIZE);
		params.stack_size = CONFIG_NET_RX_STACK_SIZE;
		params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(tc_rx_handler);
		params.p1 = rx_classes[i].fifo;
		params.prio = priority;
		params.options = 0;
		params.delay = K_FOREVER;

		NET_DBG("[%d] Starting RX handler %p stack size %d "
			"prio %d %s(%d)", i,
			rx_classes[i].handler,
			CONFIG_NET_RX_STACK_SIZE,
			thread_priority,
			IS_ENABLED(CONFIG_NET_TC_THREAD_COOPERATIVE) ?
							"coop" : "preempt",
			priority);

		skadi_fifo_init(rx_classes[i].fifo);

		tid = skadi_thread_create(&params);

		if (!tid) {
			NET_ERR("Cannot create TC handler thread %d", i);
			continue;
		}

		if (IS_ENABLED(CONFIG_THREAD_NAME)) {
			char name[MAX_NAME_LEN];

			snprintk(name, sizeof(name), "rx_q[%d]", i);
			skadi_thread_name_set(tid, name);
		}

		skadi_thread_start(tid);
	}
#endif
}
