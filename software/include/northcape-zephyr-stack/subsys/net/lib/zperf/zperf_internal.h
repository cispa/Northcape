/*
 * Copyright (c) 2016 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef __ZPERF_INTERNAL_H
#define __ZPERF_INTERNAL_H

#include <limits.h>
#include <zephyr/net/net_ip.h>
#include <zephyr/net/zperf.h>
#include <zephyr/shell/shell.h>
#include <zephyr/sys/__assert.h>

#ifdef CONFIG_SKADI_OS
#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/arpa/skadi_inet.h>
#include <zephyr/skadi/skadi_work.h>
#include <zephyr/skadi/net/skadi_net_ip.h>
#include <zephyr/skadi/net/skadi_socket_service.h>
#include <zephyr/skadi/subsystems/net/skadi_net.h>
#include <zephyr/skadi/subsystems/net/skadi_igmp.h>
#include <zephyr/skadi/subsystems/net/skadi_ipv6.h>
#include <zephyr/skadi/net/skadi_socket.h>
#include <zephyr/skadi/sys/skadi_ioctl.h>
#endif

#define IP6PREFIX_STR2(s) #s
#define IP6PREFIX_STR(p) IP6PREFIX_STR2(p)

#define MY_PREFIX_LEN 64
#define MY_PREFIX_LEN_STR IP6PREFIX_STR(MY_PREFIX_LEN)

/* Note that you can set local endpoint address in config file */
#if defined(CONFIG_NET_IPV6) && defined(CONFIG_NET_CONFIG_SETTINGS)
#define MY_IP6ADDR CONFIG_NET_CONFIG_MY_IPV6_ADDR
#define DST_IP6ADDR CONFIG_NET_CONFIG_PEER_IPV6_ADDR
#define MY_IP6ADDR_SET
#else
#define MY_IP6ADDR NULL
#define DST_IP6ADDR NULL
#endif

#if defined(CONFIG_NET_IPV4) && defined(CONFIG_NET_CONFIG_SETTINGS)
#define MY_IP4ADDR CONFIG_NET_CONFIG_MY_IPV4_ADDR
#define DST_IP4ADDR CONFIG_NET_CONFIG_PEER_IPV4_ADDR
#define MY_IP4ADDR_SET
#else
#define MY_IP4ADDR NULL
#define DST_IP4ADDR NULL
#endif

#define PACKET_SIZE_MAX CONFIG_NET_ZPERF_MAX_PACKET_SIZE

#define MY_SRC_PORT 50000
#define DEF_PORT 5001
#define DEF_PORT_STR STRINGIFY(DEF_PORT)

/* Upload defaults */
#define DEF_DURATION_SECONDS 1
#define DEF_DURATION_SECONDS_STR STRINGIFY(DEF_DURATION_SECONDS)
#define DEF_PACKET_SIZE 256
#define DEF_PACKET_SIZE_STR STRINGIFY(DEF_PACKET_SIZE)
#define DEF_RATE_KBPS 10
#define DEF_RATE_KBPS_STR STRINGIFY(DEF_RATE_KBPS)

#define ZPERF_VERSION "1.1"

struct zperf_udp_datagram {
	int32_t id;
	uint32_t tv_sec;
	uint32_t tv_usec;
} __packed;

BUILD_ASSERT(sizeof(struct zperf_udp_datagram) <= PACKET_SIZE_MAX, "Invalid PACKET_SIZE_MAX");

struct zperf_client_hdr_v1 {
	int32_t flags;
	int32_t num_of_threads;
	int32_t port;
	int32_t buffer_len;
	int32_t bandwidth;
	int32_t num_of_bytes;
};

struct zperf_server_hdr {
	int32_t flags;
	int32_t total_len1;
	int32_t total_len2;
	int32_t stop_sec;
	int32_t stop_usec;
	int32_t error_cnt;
	int32_t outorder_cnt;
	int32_t datagrams;
	int32_t jitter1;
	int32_t jitter2;
};

struct zperf_async_upload_context {
	struct k_work work;
	struct zperf_upload_params param;
	zperf_callback callback;
	void *user_data;
};

static inline uint32_t time_delta(uint32_t ts, uint32_t t)
{
	return (t >= ts) ? (t - ts) : (ULONG_MAX - ts + t);
}

int zperf_get_ipv6_addr(const char *host, const char *prefix_str, struct in6_addr *addr);
struct sockaddr_in6 *zperf_get_sin6(void);

int zperf_get_ipv4_addr(const char *host, struct in_addr *addr);
struct sockaddr_in *zperf_get_sin(void);

extern void connect_ap(char *ssid);

int zperf_prepare_upload_sock(const struct sockaddr *peer_addr, uint8_t tos,
			      int priority, int tcp_nodelay, int proto);

uint32_t zperf_packet_duration(uint32_t packet_size, uint32_t rate_in_kbps);

void zperf_async_work_submit(struct k_work *work);
void zperf_udp_uploader_init(void);
void zperf_tcp_uploader_init(void);

void zperf_shell_init(void);

#ifdef SKADI_SUBSYSTEM
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_get_ipv6_addr, const char *host, const char *prefix_str, struct in6_addr *addr);

	static inline int _skadi_zperf_get_ipv6_addr(const char *host, const char *prefix_str, struct in6_addr *addr){
		const char *host_token = skadi_cap_ops_derive_arg_ro(host, strlen(host) + 1);
		const char *prefix_token = skadi_cap_ops_derive_arg_ro(prefix_str, strlen(prefix_str) + 1);
		struct in6_addr *addr_token = skadi_cap_ops_derive_arg_wo(addr, sizeof(*addr));
		int ret;

		__ASSERT_NO_MSG(host);
		__ASSERT_NO_MSG(prefix_str);
		__ASSERT_NO_MSG(addr);

		__ASSERT_NO_MSG(host_token);
		__ASSERT_NO_MSG(prefix_token);
		__ASSERT_NO_MSG(addr_token);

		if(!host_token || !prefix_token || !addr_token){
			ret = -ENOMEM;
			goto out;
		}

		ret = __skadi_zperf_get_ipv6_addr(host_token, prefix_token, addr_token);


		out:
		if(host_token){
			skadi_cap_ops_drop(host_token);
		}

		if(prefix_token){
			skadi_cap_ops_drop(prefix_token);
		}

		if(addr_token){
			skadi_cap_ops_drop(addr_token);
		}

		return ret;
	}

	#define skadi_zperf_get_ipv6_addr(HOST, PREFIX_STR, ADDR) _skadi_zperf_get_ipv6_addr(HOST, PREFIX_STR, ADDR)

	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_get_ipv4_addr, const char *host, struct in_addr *addr);

	static inline int _skadi_zperf_get_ipv4_addr(const char *host, struct in_addr *addr){
		const char *host_token = skadi_cap_ops_derive_arg_ro(host, strlen(host) + 1);
		struct in_addr *addr_token = skadi_cap_ops_derive_arg_wo(addr, sizeof(*addr));
		int ret;

		__ASSERT_NO_MSG(host);
		__ASSERT_NO_MSG(addr);

		__ASSERT_NO_MSG(host_token);
		__ASSERT_NO_MSG(addr_token);

		if(!host_token || !addr_token){
			ret = -ENOMEM;
			goto out;
		}

		ret = __skadi_zperf_get_ipv4_addr(host_token, addr_token);


		out:
		if(host_token){
			skadi_cap_ops_drop(host_token);
		}

		if(addr_token){
			skadi_cap_ops_drop(addr_token);
		}

		return ret;
	}

	#define skadi_zperf_get_ipv4_addr(HOST, ADDR) _skadi_zperf_get_ipv4_addr(HOST, ADDR)

	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_zperf_packet_duration, uint32_t packet_size, uint32_t rate_in_kbps);

	static inline uint32_t _skadi_zperf_packet_duration(uint32_t packet_size, uint32_t rate_in_kbps){
		return __skadi_zperf_packet_duration(packet_size, rate_in_kbps);
	}

	#define skadi_zperf_packet_duration(PACKET_SIZE, RATE_IN_KBPS) _skadi_zperf_packet_duration(PACKET_SIZE, RATE_IN_KBPS)
#endif

int zperf_recv_0copy(int fd);

#endif /* __ZPERF_INTERNAL_H */
