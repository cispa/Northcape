/*
 * Copyright (c) 2017 Linaro Limited
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

#include <zephyr/net/ptp_time.h>

#if !defined(__ZEPHYR__) || defined(CONFIG_POSIX_API)

#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

#else

#include <zephyr/net/socket.h>
#include <zephyr/kernel.h>

#include <zephyr/net/net_pkt.h>

#endif

#ifdef CONFIG_SKADI_OS
#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/skadi_stdlib.h>
#include <zephyr/skadi/skadi_unistd.h>
#include <zephyr/skadi/skadi_sem.h>

#include <zephyr/skadi/arpa/skadi_inet.h>
#include <zephyr/skadi/sys/skadi_socket.h>
#include <zephyr/skadi/subsystems/ptp/skadi_ptp_clock.h>
#include <zephyr/skadi/subsystems/ptp/skadi_ptp_clock_ha1588.h>
#include <zephyr/skadi/sys/skadi_ioctl.h>
#endif

#include <zephyr/drivers/ptp_clock.h>
#include <zephyr/drivers/ptp/ptp_clock_ha1588.h>
#include <math.h>


#include <zephyr/skadi/skadi_benchmark.h>

#define BIND_PORT 8080

#ifdef CONFIG_SKADI_OS
#define CHECK(r) { if (r == -1) { printf("Error: " #r "\n"); skadi_exit(1); } }
#else
#define CHECK(r) { if (r == -1) { printf("Error: " #r "\n"); exit(1); } }
#endif


#define PACKETS_PER_DIRECTION 100

#if defined(CONFIG_SKADI_OS) && defined(CONFIG_SKADI_DEBUG) && !defined(CONFIG_PROFILING_PERF)
	static void check_capability_leak(const char *label, uint64_t *last_capabilities, const uint64_t *initial_capabilities){
		uint64_t current_capabilities = skadi_cap_ops_get_capability_count();

		if(current_capabilities > *initial_capabilities && current_capabilities - *initial_capabilities > 1000){
			printf("Capability leak suspected!\n");
		}

		printf("Current capability number %s: %"PRIu64"\ninitial capability number: %"PRIu64 " last capability number %"PRIu64" ", label, current_capabilities, *initial_capabilities, *last_capabilities);
		printf("delta last: %c%"PRIu64"\n", current_capabilities >= *last_capabilities ? '+' : '-', current_capabilities >= *last_capabilities ? current_capabilities - *last_capabilities : *last_capabilities - current_capabilities);
		printf("delta initial: %c%"PRIu64".\n", current_capabilities >= *initial_capabilities ? '+' : '-', current_capabilities - *initial_capabilities ? current_capabilities - *initial_capabilities : *initial_capabilities - current_capabilities);
		printf("allocated chunks in the allocator: %ld\n", skadi_allocator_allocated_chunks());
		*last_capabilities = current_capabilities;
	}
#elif defined(CONFIG_SKADI_OS)
	static void check_capability_leak(const char *label, uint64_t *last_capabilities, const uint64_t *initial_capabilities){
		ARG_UNUSED(label);
		ARG_UNUSED(last_capabilities);
		ARG_UNUSED(initial_capabilities);
	}
#endif

#define RX_BUFFER_SIZE 2048

struct skadi_benchmark_state rx_durations[PACKETS_PER_DIRECTION];
struct skadi_benchmark_state tx_durations[PACKETS_PER_DIRECTION];

static void evaluate_durations(bool is_rx){
	const struct skadi_benchmark_state *durations = is_rx ? rx_durations : tx_durations;
	char buffer[100];

	snprintf(buffer, sizeof(buffer), "%s network stack processing durations samples", is_rx ? "rx" : "tx");

	skadi_benchmark_evaluate_samples(durations, PACKETS_PER_DIRECTION, 0, buffer);
}

#ifdef CONFIG_SKADI_OS

	struct k_sem tx_time_sema;

	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, skadi_network_overhead_tx_completion_callback, uint8_t *data)
		skadi_sem_give(&tx_time_sema);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_network_overhead_tx_completion_callback)
#endif

#ifdef CONFIG_SKADI_OS
#define ADDR_STR_LEN 32
SKADI_SUBSYSTEM_MAIN(void)
#else
int main(void)
#endif
{
	int serv;
	struct sockaddr_in bind_addr;
	static const uint8_t ts_mask = SOF_TIMESTAMPING_TX_HARDWARE | SOF_TIMESTAMPING_RX_HARDWARE; 
	struct sockaddr_in client_addr;
	socklen_t client_addr_len = sizeof(client_addr);
	const struct device *ha1588_dev = DEVICE_DT_GET_ONE(ha1588_rtc_1_0);
	bool started_perf = false;

#ifdef CONFIG_SKADI_OS
	char *addr_str = skadi_allocator_alloc_rw(ADDR_STR_LEN);
	uint64_t initial_capabilities = skadi_cap_ops_get_capability_count();
	uint64_t last_capabilities = initial_capabilities;
	const bool zerocopy_enabled = true;
	const void *tx_callback = SKADI_SUBSYSTEM_FUNCTION_POINTER(skadi_network_overhead_tx_completion_callback);
	void *buf;
	ssize_t out_size;
	void *buf_ptr = skadi_cap_ops_derive_arg_wo(&buf, sizeof(void*));
	ssize_t *out_size_ptr = skadi_cap_ops_derive_arg_wo(&out_size, sizeof(ssize_t *));
	struct sockaddr_in *addr_ptr;
	socklen_t *addrlen_ptr;

	skadi_evaluate_boot_time();

	/* also read by the implementation... */
	addr_ptr = skadi_cap_ops_derive_arg(&client_addr, sizeof(client_addr));
	addrlen_ptr = skadi_cap_ops_derive_arg(&client_addr_len, sizeof(client_addr_len));

	__ASSERT_NO_MSG(buf_ptr);
	__ASSERT_NO_MSG(out_size_ptr);
	__ASSERT_NO_MSG(addr_ptr);
	__ASSERT_NO_MSG(addrlen_ptr);

	if(!buf_ptr || !out_size_ptr || !addr_ptr || !addrlen_ptr){
		return -ENOMEM;
	}

	__ASSERT_NO_MSG(addr_str);

	if(!addr_str){
		return -ENOMEM;
	}

	skadi_sem_init(&tx_time_sema, 0, 1);

	serv = skadi_socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
#else
	serv = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
#endif
	CHECK(serv);

	bind_addr.sin_family = AF_INET;
	bind_addr.sin_addr.s_addr = htonl(INADDR_ANY);
	bind_addr.sin_port = htons(BIND_PORT);

#ifdef CONFIG_SKADI_OS
	CHECK(skadi_bind(serv, (struct sockaddr *)&bind_addr, sizeof(bind_addr)));

	CHECK(skadi_setsockopt(serv, SOL_SOCKET, SO_ZEROCOPY, &zerocopy_enabled, sizeof(zerocopy_enabled)));
	CHECK(skadi_setsockopt(serv, SOL_SOCKET, SO_TIMESTAMPING, &ts_mask, sizeof(ts_mask)));
	CHECK(skadi_setsockopt(serv, SOL_SOCKET, SO_ZEROCOPY_TX_CALLBACK, &tx_callback, sizeof(tx_callback)));
#else
	CHECK(bind(serv, (struct sockaddr *)&bind_addr, sizeof(bind_addr)));
	CHECK(setsockopt(serv, SOL_SOCKET, SO_TIMESTAMPING, &ts_mask, sizeof(ts_mask)));
#endif

	printf("Send %d UDP messages to measurement server at UDP "
	       "port %d...\n", PACKETS_PER_DIRECTION, BIND_PORT);

	/**
	 * Wait for client to send a few packets, then send a few packets ourselves
	 * Measure current time - RX time, TX time - current time WRT API function called
	 */
	while (1) {
#ifndef CONFIG_SKADI_OS
		char addr_str[32] = {0};
#endif
		const char *data = "foobar\n";
		size_t len = strlen(data) + 1;
#ifdef CONFIG_SKADI_OS
		const char *data_token = skadi_cap_ops_derive_arg_ro(data, len);
#endif
		int received = 0;
		int sent = 0;
		struct net_ptp_time timestamp = {0};
		struct net_ptp_time ref_time;
		int64_t duration;
#ifdef CONFIG_SKADI_OS
		struct net_ptp_time *timestamp_ptr = skadi_cap_ops_derive_arg_wo(&timestamp, sizeof(timestamp));
		__ASSERT_NO_MSG(data_token);
		__ASSERT_NO_MSG(timestamp_ptr);

		if(!data_token || !timestamp_ptr){
			printf("Error: Could not derive data!");
			return -ENOMEM;
		}
#endif
		skadi_benchmark_prepare_sample(&rx_durations[0]);
		do {
			bool timestamp_found = false;
#ifdef CONFIG_SKADI_OS
			check_capability_leak("before ioctl", &last_capabilities, &initial_capabilities);
			CHECK(skadi_ioctl(serv, ZFD_IOCTL_ZEROCOPY_GETBUF, (void**) buf_ptr, out_size_ptr, addr_ptr, addrlen_ptr, timestamp_ptr));
			CHECK(skadi_ptp_clock_get(ha1588_dev, &ref_time));
			/* no failure condition */
			timestamp_found = true;
#else		
			struct cmsghdr *cmsg;
			struct msghdr msghdr = {0};
			char buf[RX_BUFFER_SIZE];
			struct iovec iov = {
				.iov_base = buf,
				.iov_len = sizeof(buf)-1,
			};
			uint8_t ctrl[CMSG_SPACE(sizeof(struct net_ptp_time))] = {0};

			
			msghdr.msg_iov = &iov;
			msghdr.msg_iovlen = 1;
			msghdr.msg_control = ctrl;
			msghdr.msg_controllen = sizeof(ctrl);
			msghdr.msg_name = &client_addr;
			msghdr.msg_namelen = client_addr_len;

			CHECK(recvmsg(serv, &msghdr, 0));
			CHECK(ptp_clock_get(ha1588_dev, &ref_time));

			for (cmsg = CMSG_FIRSTHDR(&msghdr); cmsg != NULL; cmsg = CMSG_NXTHDR(&msghdr, cmsg)) {
				if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SO_TIMESTAMPING) {
					memcpy(&timestamp, CMSG_DATA(cmsg), sizeof(struct net_ptp_time));
					timestamp_found = true;
				}
			}
			// guaranteed to be in the buffer, as iov_len is initialized to buffer size - 1
			buf[msghdr.msg_iov->iov_len] = '\0';
			__ASSERT_NO_MSG(timestamp_found);
#endif

#ifdef CONFIG_SKADI_OS
			skadi_inet_ntop(client_addr.sin_family, &client_addr.sin_addr, addr_str, ADDR_STR_LEN);
#else
			inet_ntop(client_addr.sin_family, &client_addr.sin_addr,
			  addr_str, sizeof(addr_str));
#endif

			duration = net_ptp_time_to_ns(&ref_time) - net_ptp_time_to_ns(&timestamp);
			
			skadi_benchmark_add_sample(&rx_durations[received], duration);
			
			if(received+1 < PACKETS_PER_DIRECTION){
				skadi_benchmark_prepare_sample(&rx_durations[received+1]);
			}

			printf("Received message #%d from %s at %"PRIu64".%"PRIu32"s content %s processing delay: %"PRId64"ns\n", received++, addr_str, timestamp.second, timestamp.nanosecond, (const char *)buf, duration);

			if(!started_perf){
				started_perf = true;
				skadi_perf_start(1000);
			}

#ifdef CONFIG_SKADI_OS
			CHECK(skadi_ioctl(serv, ZFD_IOCTL_ZEROCOPY_FREEBUF, buf));
#endif
		} while(received < PACKETS_PER_DIRECTION);

		skadi_perf_cancel();

		skadi_perf_start(1000);

		skadi_benchmark_prepare_sample(&tx_durations[0]);
		do {
#ifdef CONFIG_SKADI_OS
			check_capability_leak("before send", &last_capabilities, &initial_capabilities);
			socklen_t timestamp_len = sizeof(timestamp);
			
			CHECK(skadi_ptp_clock_get(ha1588_dev, &ref_time));

			CHECK(skadi_zsock_sendto_0copy(serv, data_token, len, 0, (struct sockaddr*) &client_addr, client_addr_len));
			/* callback will tell us when the last fragment has been transmitted */
			skadi_sem_take(&tx_time_sema, K_FOREVER);

			CHECK(skadi_getsockopt(serv, SOL_SOCKET, SO_LAST_TXTIME, &timestamp, &timestamp_len));

			duration = net_ptp_time_to_ns(&timestamp) - net_ptp_time_to_ns(&ref_time);

			skadi_benchmark_add_sample(&tx_durations[sent], duration);

			if(sent+1 < PACKETS_PER_DIRECTION){
				skadi_benchmark_prepare_sample(&tx_durations[sent+1]);
			}
#else
			socklen_t timestamp_len = sizeof(timestamp);
			
			CHECK(ptp_clock_get(ha1588_dev, &ref_time));

			CHECK(sendto(serv, data, len, 0, (struct sockaddr*) &client_addr, client_addr_len));
			// time to collect timestamp
			sleep(1);

			CHECK(getsockopt(serv, SOL_SOCKET, SO_LAST_TXTIME, &timestamp, &timestamp_len));

			duration = net_ptp_time_to_ns(&timestamp) - net_ptp_time_to_ns(&ref_time);

			skadi_benchmark_add_sample(&tx_durations[sent], duration);

			if(sent+1 < PACKETS_PER_DIRECTION){
				skadi_benchmark_prepare_sample(&tx_durations[sent+1]);
			}
#endif
			printf("Sent message #%d to %s at %"PRIu64".%"PRIu32" s valid: %d processing delay: %"PRId64"ns\n", sent++, addr_str, timestamp.second, timestamp.nanosecond, false, duration);
		} while(sent < PACKETS_PER_DIRECTION);

		skadi_perf_cancel();

		evaluate_durations(true);
		evaluate_durations(false);

#ifdef CONFIG_SKADI_OS
		skadi_cap_ops_drop(timestamp_ptr);
#endif

#if defined(__ZEPHYR__) && defined(CONFIG_NET_BUF_POOL_USAGE)
		struct k_mem_slab *rx, *tx;
		struct net_buf_pool *rx_data, *tx_data;

		net_pkt_get_info(&rx, &tx, &rx_data, &tx_data);
		printf("rx buf: %d, tx buf: %d\n",
		       atomic_get(&rx_data->avail_count), atomic_get(&tx_data->avail_count));
#endif

	}
	return 0;
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_MAIN_END
#endif
