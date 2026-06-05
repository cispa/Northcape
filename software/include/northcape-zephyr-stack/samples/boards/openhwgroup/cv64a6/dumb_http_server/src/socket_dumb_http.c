/*
 * Copyright (c) 2017 Linaro Limited
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

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

#include <zephyr/skadi/arpa/skadi_inet.h>
#include <zephyr/skadi/sys/skadi_socket.h>
#endif

#include <zephyr/skadi/skadi_benchmark.h>

#define BIND_PORT 8080

#ifndef USE_BIG_PAYLOAD
#define USE_BIG_PAYLOAD 1
#endif

#ifdef CONFIG_SKADI_OS
#define CHECK(r) { if (r == -1) { printf("Error: " #r "\n"); skadi_exit(1); } }
#else
#define CHECK(r) { if (r == -1) { printf("Error: " #r "\n"); exit(1); } }
#endif

static const char content[] = {
#if USE_BIG_PAYLOAD
    #include "response_big.html.bin.inc"
#else
    #include "response_small.html.bin.inc"
#endif
};

/* If accept returns an error, then we are probably running
 * out of resource. Sleep a small amount of time in order the
 * system to cool down.
 */
#define ACCEPT_ERROR_WAIT 100 /* in ms */

static void sleep_after_error(unsigned int amount)
{
#if defined(CONFIG_SKADI_OS)
	skadi_msleep(amount);
#elif defined(__ZEPHYR__)
	k_msleep(amount);
#else
	usleep(amount * 1000U);
#endif
}

#ifdef CONFIG_SKADI_OS
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
#endif

#define RX_BUFFER_SIZE 2048

#ifdef CONFIG_SKADI_OS
#define ADDR_STR_LEN 32
SKADI_SUBSYSTEM_MAIN(void)
#else
int main(void)
#endif
{
	int serv;
	struct sockaddr_in bind_addr;
	static int counter;
	int ret;
#ifdef CONFIG_SKADI_OS
	char *addr_str;
	uint64_t initial_capabilities;
	uint64_t last_capabilities;
#endif

	skadi_evaluate_boot_time();

#ifdef CONFIG_SKADI_OS
	addr_str = skadi_allocator_alloc_rw(ADDR_STR_LEN);
	initial_capabilities = skadi_cap_ops_get_capability_count();
	last_capabilities = initial_capabilities;

	__ASSERT_NO_MSG(addr_str);

	if(!addr_str){
		return -ENOMEM;
	}

	serv = skadi_socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
#else
	serv = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
#endif
	CHECK(serv);

	bind_addr.sin_family = AF_INET;
	bind_addr.sin_addr.s_addr = htonl(INADDR_ANY);
	bind_addr.sin_port = htons(BIND_PORT);

#ifdef CONFIG_SKADI_OS
	CHECK(skadi_bind(serv, (struct sockaddr *)&bind_addr, sizeof(bind_addr)));

	CHECK(skadi_listen(serv, 5));
#else
	CHECK(bind(serv, (struct sockaddr *)&bind_addr, sizeof(bind_addr)));

	CHECK(listen(serv, 5));
#endif

	printf("Single-threaded dumb HTTP server waits for a connection on "
	       "port %d...\n", BIND_PORT);

	while (1) {
		struct sockaddr_in client_addr;
		socklen_t client_addr_len = sizeof(client_addr);
#ifndef CONFIG_SKADI_OS
		char addr_str[32];
#endif
		int req_state = 0;
		const char *data;
		size_t len;

#ifdef CONFIG_SKADI_OS
		check_capability_leak("before accept", &last_capabilities, &initial_capabilities);
#endif

#ifdef CONFIG_SKADI_OS
		int client = skadi_accept(serv, (struct sockaddr *)&client_addr,
				    &client_addr_len);
#else
		int client = accept(serv, (struct sockaddr *)&client_addr,
				    &client_addr_len);
#endif
		if (client < 0) {
			printf("Error in accept: %d - continuing\n", errno);
			sleep_after_error(ACCEPT_ERROR_WAIT);
			continue;
		}

#ifdef CONFIG_SKADI_OS
		skadi_inet_ntop(client_addr.sin_family, &client_addr.sin_addr, addr_str, ADDR_STR_LEN);
#else
		inet_ntop(client_addr.sin_family, &client_addr.sin_addr,
			  addr_str, sizeof(addr_str));
#endif
		printf("Connection #%d from %s\n", counter++, addr_str);

		/* Discard HTTP request (or otherwise client will get
		 * connection reset error).
		 */
		while (1) {
			ssize_t r;
			char c;
			char buf[RX_BUFFER_SIZE];
			bool continue_loop = true;

#ifdef CONFIG_SKADI_OS
			r = skadi_recv(client, buf, RX_BUFFER_SIZE, 0);
#else
			r = recv(client, buf, RX_BUFFER_SIZE, 0);
#endif
			if (r == 0) {
				goto close_client;
			}

			if (r < 0) {
				if (errno == EAGAIN || errno == EINTR) {
					continue;
				}

				printf("Got error %d when receiving from "
				       "socket\n", errno);
				goto close_client;
			}

			for(ssize_t i = 0; i < r; i++){
				c = buf[i];
				if (req_state == 0 && c == '\r') {
					req_state++;
				} else if (req_state == 1 && c == '\n') {
					req_state++;
				} else if (req_state == 2 && c == '\r') {
					req_state++;
				} else if (req_state == 3 && c == '\n') {
					continue_loop = false;
					break;
				} else {
					req_state = 0;
				}
			}

			if(!continue_loop){
				break;
			}
		}

		data = content;
		len = sizeof(content);
		while (len) {
#ifdef CONFIG_SKADI_OS
			int sent_len = skadi_send(client, data, len, 0);
#else
			int sent_len = send(client, data, len, 0);
#endif

			if (sent_len == -1) {
				printf("Error sending data to peer, errno: %d\n", errno);
				break;
			}
			data += sent_len;
			len -= sent_len;
		}

close_client:
#ifdef CONFIG_SKADI_OS
		ret = skadi_close(client);
#else
		ret = close(client);
#endif
		if (ret == 0) {
			printf("Connection from %s closed\n", addr_str);
		} else {
			printf("Got error %d while closing the "
			       "socket\n", errno);
		}


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
