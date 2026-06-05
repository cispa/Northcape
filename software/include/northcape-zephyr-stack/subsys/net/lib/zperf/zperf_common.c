/*
 * Copyright (c) 2022 Nordic Semiconductor ASA
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/init.h>
#include <zephyr/logging/log.h>
#include <zephyr/net/socket.h>

#include "zperf_internal.h"
#include "zperf_session.h"

LOG_MODULE_REGISTER(net_zperf, CONFIG_NET_ZPERF_LOG_LEVEL);

/* Get some useful debug routings from net_private.h, requires
 * that NET_LOG_ENABLED is set.
 */
#define NET_LOG_ENABLED 1
#include "net_private.h"

#include "ipv6.h" /* to get infinite lifetime */

static struct sockaddr_in6 in6_addr_my = {
	.sin6_family = AF_INET6,
	.sin6_port = htons(MY_SRC_PORT),
};

static struct sockaddr_in in4_addr_my = {
	.sin_family = AF_INET,
	.sin_port = htons(MY_SRC_PORT),
};

struct sockaddr_in6 *zperf_get_sin6(void)
{
	return &in6_addr_my;
}

struct sockaddr_in *zperf_get_sin(void)
{
	return &in4_addr_my;
}

#define ZPERF_WORK_Q_THREAD_PRIORITY                                                               \
	CLAMP(CONFIG_ZPERF_WORK_Q_THREAD_PRIORITY, K_HIGHEST_APPLICATION_THREAD_PRIO,              \
	      K_LOWEST_APPLICATION_THREAD_PRIO)
K_THREAD_STACK_DEFINE(zperf_work_q_stack, CONFIG_ZPERF_WORK_Q_STACK_SIZE);

static struct k_work_q zperf_work_q;

int zperf_get_ipv6_addr(const char *host, const char *prefix_str, struct in6_addr *addr)
{
	struct net_if_ipv6_prefix *prefix;
	struct net_if_addr *ifaddr;
	int prefix_len;
	int ret;

	if (!host) {
		return -EINVAL;
	}

#ifdef CONFIG_SKADI_OS
	ret = skadi_net_addr_pton(AF_INET6, host, addr);
#else
	ret = net_addr_pton(AF_INET6, host, addr);
#endif
	if (ret < 0) {
		return -EINVAL;
	}

	prefix_len = strtoul(prefix_str, NULL, 10);

#ifdef CONFIG_SKADI_OS
	ifaddr = skadi_net_if_ipv6_addr_add(skadi_net_if_get_default(),
				      addr, NET_ADDR_MANUAL, 0);
#else
	ifaddr = net_if_ipv6_addr_add(net_if_get_default(),
				      addr, NET_ADDR_MANUAL, 0);
#endif
	if (!ifaddr) {
		NET_ERR("Cannot set IPv6 address %s", host);
		return -EINVAL;
	}

#ifdef CONFIG_SKADI_OS
	skadi_cap_ops_drop(ifaddr);
#endif

#ifdef CONFIG_SKADI_OS
	prefix = skadi_net_if_ipv6_prefix_add(skadi_net_if_get_default(),
					addr, prefix_len,
					NET_IPV6_ND_INFINITE_LIFETIME);
#else
	prefix = net_if_ipv6_prefix_add(net_if_get_default(),
					addr, prefix_len,
					NET_IPV6_ND_INFINITE_LIFETIME);
#endif
	if (!prefix) {
		NET_ERR("Cannot set IPv6 prefix %s", prefix_str);
		return -EINVAL;
	}

#ifdef CONFIG_SKADI_OS
	skadi_cap_ops_drop(prefix);
#endif

	return 0;
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zperf_get_ipv6_addr, const char *host, const char *prefix_str, struct in6_addr *addr)
	return zperf_get_ipv6_addr(host, prefix_str, addr);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zperf_get_ipv6_addr)
#endif

int zperf_get_ipv4_addr(const char *host, struct in_addr *addr)
{
	struct net_if_addr *ifaddr;
	int ret;

	if (!host) {
		return -EINVAL;
	}

#ifdef CONFIG_SKADI_OS
	ret = skadi_net_addr_pton(AF_INET, host, addr);
#else
	ret = net_addr_pton(AF_INET, host, addr);
#endif
	if (ret < 0) {
		return -EINVAL;
	}

#ifdef CONFIG_SKADI_OS
	ifaddr = skadi_net_if_ipv4_addr_add(skadi_net_if_get_default(),
				      addr, NET_ADDR_MANUAL, 0);
#else
	ifaddr = net_if_ipv4_addr_add(net_if_get_default(),
				      addr, NET_ADDR_MANUAL, 0);
#endif
	if (!ifaddr) {
		NET_ERR("Cannot set IPv4 address %s", host);
		return -EINVAL;
	}
#ifdef CONFIG_SKADI_OS
	skadi_cap_ops_drop(ifaddr);
#endif

	return 0;
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zperf_get_ipv4_addr, const char *host, struct in_addr *addr)
	return zperf_get_ipv4_addr(host, addr);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zperf_get_ipv4_addr)
#endif

int zperf_prepare_upload_sock(const struct sockaddr *peer_addr, uint8_t tos,
			      int priority, int tcp_nodelay, int proto)
{
	socklen_t addrlen = peer_addr->sa_family == AF_INET6 ?
			    sizeof(struct sockaddr_in6) :
			    sizeof(struct sockaddr_in);
	int type = (proto == IPPROTO_UDP) ? SOCK_DGRAM : SOCK_STREAM;
	int sock = -1;
	int ret;

	switch (peer_addr->sa_family) {
	case AF_INET:
		if (!IS_ENABLED(CONFIG_NET_IPV4)) {
			NET_ERR("IPv4 not available.");
			return -EINVAL;
		}

#ifdef CONFIG_SKADI_OS
		sock = skadi_zsock_socket(AF_INET, type, proto);
#else
		sock = zsock_socket(AF_INET, type, proto);
#endif
		if (sock < 0) {
			NET_ERR("Cannot create IPv4 network socket (%d)",
				errno);
			return -errno;
		}

		if (tos > 0) {
#ifdef CONFIG_SKADI_OS
			if (skadi_zsock_setsockopt(sock, IPPROTO_IP, IP_TOS,
					     &tos, sizeof(tos)) != 0) {
#else
			if (zsock_setsockopt(sock, IPPROTO_IP, IP_TOS,
					     &tos, sizeof(tos)) != 0) {
#endif
				NET_WARN("Failed to set IP_TOS socket option. "
					 "Please enable CONFIG_NET_CONTEXT_DSCP_ECN.");
			}
		}

		break;

	case AF_INET6:
		if (!IS_ENABLED(CONFIG_NET_IPV6)) {
			NET_ERR("IPv6 not available.");
			return -EINVAL;
		}

#ifdef CONFIG_SKADI_OS
		sock = skadi_zsock_socket(AF_INET6, type, proto);
#else
		sock = zsock_socket(AF_INET6, type, proto);
#endif
		if (sock < 0) {
			NET_ERR("Cannot create IPv6 network socket (%d)",
				errno);
			return -errno;
		}

		if (tos >= 0) {
#ifdef CONFIG_SKADI_OS
			if (skadi_zsock_setsockopt(sock, IPPROTO_IPV6, IPV6_TCLASS,
					     &tos, sizeof(tos)) != 0) {
#else
			if (zsock_setsockopt(sock, IPPROTO_IPV6, IPV6_TCLASS,
					     &tos, sizeof(tos)) != 0) {
#endif
				NET_WARN("Failed to set IPV6_TCLASS socket option. "
					 "Please enable CONFIG_NET_CONTEXT_DSCP_ECN.");
			}
		}

		break;

	default:
		LOG_ERR("Invalid address family (%d)", peer_addr->sa_family);
		return -EINVAL;
	}

	if (IS_ENABLED(CONFIG_NET_CONTEXT_PRIORITY) && priority >= 0) {
		uint8_t prio = priority;

		if (!IS_ENABLED(CONFIG_NET_ALLOW_ANY_PRIORITY) &&
		    (prio >= NET_MAX_PRIORITIES)) {
			NET_ERR("Priority %d is too large, maximum allowed is %d",
				prio, NET_MAX_PRIORITIES - 1);
			ret = -EINVAL;
			goto error;
		}
#ifdef CONFIG_SKADI_OS
		if (skadi_zsock_setsockopt(sock, SOL_SOCKET, SO_PRIORITY,
				     &prio,
				     sizeof(prio)) != 0) {
#else
		if (zsock_setsockopt(sock, SOL_SOCKET, SO_PRIORITY,
				     &prio,
				     sizeof(prio)) != 0) {
#endif
			NET_WARN("Failed to set SOL_SOCKET - SO_PRIORITY socket option.");
			ret = -errno;
			goto error;
		}
	}

#ifdef CONFIG_SKADI_OS
	if (proto == IPPROTO_TCP && tcp_nodelay &&
	    skadi_zsock_setsockopt(sock, IPPROTO_TCP, TCP_NODELAY,
			     &tcp_nodelay,
			     sizeof(tcp_nodelay)) != 0) {
		NET_WARN("Failed to set IPPROTO_TCP - TCP_NODELAY socket option.");
		ret = -errno;
		goto error;
	}
#else
	if (proto == IPPROTO_TCP && tcp_nodelay &&
	    zsock_setsockopt(sock, IPPROTO_TCP, TCP_NODELAY,
			     &tcp_nodelay,
			     sizeof(tcp_nodelay)) != 0) {
		NET_WARN("Failed to set IPPROTO_TCP - TCP_NODELAY socket option.");
		ret = -errno;
		goto error;
	}
#endif

#ifdef CONFIG_SKADI_OS
	ret = skadi_zsock_connect(sock, peer_addr, addrlen);
#else
	ret = zsock_connect(sock, peer_addr, addrlen);
#endif
	if (ret < 0) {
		NET_ERR("Connect failed (%d)", errno);
		ret = -errno;
		goto error;
	}

	return sock;

error:
#ifdef CONFIG_SKADI_OS
	skadi_zsock_close(sock);
#else
	zsock_close(sock);
#endif
	return ret;
}

uint32_t zperf_packet_duration(uint32_t packet_size, uint32_t rate_in_kbps)
{
	return (uint32_t)(((uint64_t)packet_size * 8U * USEC_PER_SEC) /
			  (rate_in_kbps * 1024U));
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(uint32_t, __skadi_zperf_packet_duration, uint32_t packet_size, uint32_t rate_in_kbps)
	return zperf_packet_duration(packet_size, rate_in_kbps);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zperf_packet_duration)
#endif

#ifdef CONFIG_SKADI_OS
void zperf_async_work_submit(struct k_work *work)
{
	skadi_work_submit_to_queue(&zperf_work_q, work);
}
#else
void zperf_async_work_submit(struct k_work *work)
{
	k_work_submit_to_queue(&zperf_work_q, work);
}
#endif

#ifdef CONFIG_SKADI_NET_ZEROCOPY
int zperf_recv_0copy(int fd){
	void *buf, **buf_ptr = skadi_cap_ops_derive_arg_wo(&buf, sizeof(void*));
	ssize_t out_size, *out_size_ptr = skadi_cap_ops_derive_arg_wo(&out_size, sizeof(ssize_t *));

	__ASSERT_NO_MSG(buf_ptr);
	__ASSERT_NO_MSG(out_size_ptr);

	if(!buf_ptr || !out_size_ptr){
		goto out;
	}

	/* we do not care about other party's address, timestamp */
	int err = skadi_ioctl(fd, ZFD_IOCTL_ZEROCOPY_GETBUF, buf_ptr, out_size_ptr, NULL, 0, NULL);

	if(err){
		LOG_ERR("Could not getbuf via ioctl: %s (%d)", strerror(err), -err);
		goto out;
	}

	/* we do not actually do anything with the buffer... */

	err = skadi_ioctl(fd, ZFD_IOCTL_ZEROCOPY_FREEBUF, buf);

	if(err){
		LOG_ERR("Could not freebuf via ioctl: %s (%d)", strerror(err), -err);
	}

	out:
	if(buf_ptr){
		skadi_cap_ops_drop(buf_ptr);
	}
	if(out_size_ptr){
		skadi_cap_ops_drop(out_size_ptr);
	}
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmaybe-uninitialized"
	if(!err){
		/* caller needs output size */
		err = out_size;
	}

	return err;
#pragma GCC diagnostic pop
}
#endif

static int zperf_init(void)
{

#ifdef CONFIG_SKADI_OS
	skadi_work_queue_init(&zperf_work_q);
	skadi_work_queue_start(&zperf_work_q, zperf_work_q_stack,
			   K_THREAD_STACK_SIZEOF(zperf_work_q_stack), ZPERF_WORK_Q_THREAD_PRIORITY,
			   NULL);
	skadi_thread_name_set(&zperf_work_q.thread, "zperf_work_q");
#else
	k_work_queue_init(&zperf_work_q);
	k_work_queue_start(&zperf_work_q, zperf_work_q_stack,
			   K_THREAD_STACK_SIZEOF(zperf_work_q_stack), ZPERF_WORK_Q_THREAD_PRIORITY,
			   NULL);
	k_thread_name_set(&zperf_work_q.thread, "zperf_work_q");
#endif

	zperf_udp_uploader_init();
	zperf_tcp_uploader_init();

	zperf_session_init();

	if (IS_ENABLED(CONFIG_NET_SHELL)) {
#ifdef CONFIG_SKADI_OS
		/* done in the shell itself*/
#else
		zperf_shell_init();
#endif
	}

	return 0;
}

SYS_INIT(zperf_init, APPLICATION, CONFIG_KERNEL_INIT_PRIORITY_DEFAULT);
