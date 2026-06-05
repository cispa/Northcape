/*
 * Copyright (c) 2015 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/logging/log.h>
LOG_MODULE_DECLARE(net_zperf, CONFIG_NET_ZPERF_LOG_LEVEL);

#include <zephyr/arch/cache.h>

#include <zephyr/kernel.h>

#include <errno.h>

#include <zephyr/net/socket.h>
#include <zephyr/net/zperf.h>
#include <zephyr/skadi/skadi_benchmark.h>

#include "zperf_internal.h"

static char sample_packet[PACKET_SIZE_MAX];
#ifdef CONFIG_SKADI_NET_ZEROCOPY
static const char *sample_packet_token;
#endif

static struct zperf_async_upload_context tcp_async_upload_ctx;

#if defined(CONFIG_SKADI_OS) && defined(CONFIG_SKADI_NET_ZEROCOPY)
	static void enable_0copy(int sock){
		const bool zerocopy_enabled = true;
		int ret = skadi_zsock_setsockopt(sock, SOL_SOCKET, SO_ZEROCOPY, &zerocopy_enabled, sizeof(zerocopy_enabled));

		__ASSERT(!ret, "Could not enable zerocopy (-%d)", ret);
		(void) ret;
		/* no callback needed, as token is static */
	}
#else
	static void enable_0copy(int sock){
		/* nothing */
	}
#endif

static ssize_t sendall(int sock, const void *buf, size_t len)
{
	while (len) {
#if defined(CONFIG_SKADI_OS) && defined(CONFIG_SKADI_NET_ZEROCOPY)
		ssize_t out_len = skadi_zsock_send_0copy(sock, buf, len, 0);
#elif defined(CONFIG_SKADI_OS)
		ssize_t out_len = skadi_zsock_send(sock, buf, len, 0);
#else
		ssize_t out_len = zsock_send(sock, buf, len, 0);
#endif

		if (out_len < 0) {
			return out_len;
		}

		buf = (const char *)buf + out_len;
		len -= out_len;
	}

	return 0;
}

static int tcp_upload(int sock,
		      unsigned int duration_in_ms,
		      unsigned int packet_size,
		      struct zperf_results *results)
{
#ifdef CONFIG_SKADI_OS
	k_timepoint_t end = skadi_sys_timepoint_calc(K_MSEC(duration_in_ms));
#else
	k_timepoint_t end = sys_timepoint_calc(K_MSEC(duration_in_ms));
#endif
	int64_t start_time, end_time;
	uint32_t nb_packets = 0U, nb_errors = 0U;
	uint32_t alloc_errors = 0U;
	int ret = 0;

	if (packet_size > PACKET_SIZE_MAX) {
		NET_WARN("Packet size too large! max size: %u\n",
			PACKET_SIZE_MAX);
		packet_size = PACKET_SIZE_MAX;
	}

	/* Start the loop */
#ifdef CONFIG_SKADI_OS
	start_time = skadi_uptime_ticks();
#else
	start_time = k_uptime_ticks();
#endif

	(void)memset(sample_packet, 'z', sizeof(sample_packet));

	/* Set the "flags" field in start of the packet to be 0.
	 * As the protocol is not properly described anywhere, it is
	 * not certain if this is a proper thing to do.
	 */
	(void)memset(sample_packet, 0, sizeof(uint32_t));

	do {
		/* Send the packet */
#ifdef CONFIG_SKADI_NET_ZEROCOPY
		/* need a readable token here */
		ret = sendall(sock, sample_packet_token, packet_size);
#else
		ret = sendall(sock, sample_packet, packet_size);
#endif
		if (ret < 0) {
			if (nb_errors == 0 && ret != -ENOMEM) {
				NET_ERR("Failed to send the packet (%d)", errno);
			}

			nb_errors++;

			if (errno == -ENOMEM) {
				/* Ignore memory errors as we just run out of
				 * buffers which is kind of expected if the
				 * buffer count is not optimized for the test
				 * and device.
				 */
				alloc_errors++;
			} else {
				ret = -errno;
				break;
			}
		} else {
			nb_packets++;
		}

#if defined(CONFIG_ARCH_POSIX)
		k_busy_wait(100 * USEC_PER_MSEC);
#elif defined(CONFIG_SKADI_OS)
		skadi_subsystem_yield();
#else
		k_yield();
#endif

#ifdef CONFIG_SKADI_OS
	} while (!skadi_sys_timepoint_expired(end));

	end_time = skadi_uptime_ticks();
#else
	} while (!sys_timepoint_expired(end));
	
	end_time = k_uptime_ticks();
#endif

	/* Add result coming from the client */
	results->nb_packets_sent = nb_packets;
	results->client_time_in_us =
				k_ticks_to_us_ceil64(end_time - start_time);
	results->packet_size = packet_size;
	results->nb_packets_errors = nb_errors;

	if (alloc_errors > 0) {
		NET_WARN("There was %u network buffer allocation "
			 "errors during send.\nConsider increasing the "
			 "value of CONFIG_NET_BUF_TX_COUNT and\n"
			 "optionally CONFIG_NET_PKT_TX_COUNT Kconfig "
			 "options.",
			 alloc_errors);
	}

	if (ret < 0) {
		return ret;
	}

	return 0;
}

int zperf_tcp_upload(const struct zperf_upload_params *param,
		     struct zperf_results *result)
{
	int sock;
	int ret;

	if (param == NULL || result == NULL) {
		return -EINVAL;
	}


	skadi_perf_start(1000);

	sock = zperf_prepare_upload_sock(&param->peer_addr, param->options.tos,
					 param->options.priority, param->options.tcp_nodelay,
					 IPPROTO_TCP);
	if (sock < 0) {
		return sock;
	}

	enable_0copy(sock);

	ret = tcp_upload(sock, param->duration_ms, param->packet_size, result);

#ifdef CONFIG_SKADI_OS
	skadi_zsock_close(sock);
#else
	zsock_close(sock);
#endif


    skadi_perf_cancel();

	return ret;
}
#ifdef CONFIG_SKADI_OS
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zperf_tcp_upload, const struct zperf_upload_params *param, struct zperf_results *result)
		return zperf_tcp_upload(param, result);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zperf_tcp_upload)
#endif


#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(tcp_upload_cb, enum zperf_status status, struct zperf_results *result, void *user_data);
#endif


#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, tcp_upload_async_work, struct k_work *work)
#else
static void tcp_upload_async_work(struct k_work *work)
#endif
{
#ifdef CONFIG_SKADI_OS
	struct zperf_async_upload_context *upload_ctx = work->user_data;
#else
	struct zperf_async_upload_context *upload_ctx =
		CONTAINER_OF(work, struct zperf_async_upload_context, work);
#endif
	struct zperf_results result = { 0 };
	int ret;
	struct zperf_upload_params param = upload_ctx->param;
	int sock;

	__ASSERT_NO_MSG(upload_ctx);

#ifdef CONFIG_SKADI_OS
	tcp_upload_cb(ZPERF_SESSION_STARTED, NULL, upload_ctx->user_data, upload_ctx->callback);
#else
	upload_ctx->callback(ZPERF_SESSION_STARTED, NULL,
			     upload_ctx->user_data);
#endif

	sock = zperf_prepare_upload_sock(&param.peer_addr, param.options.tos,
					 param.options.priority, param.options.tcp_nodelay,
					 IPPROTO_TCP);

	if (sock < 0) {
#ifdef CONFIG_SKADI_OS
        skadi_perf_cancel();
		tcp_upload_cb(ZPERF_SESSION_ERROR, NULL, upload_ctx->user_data, upload_ctx->callback);
#else
		upload_ctx->callback(ZPERF_SESSION_ERROR, NULL,
			     	 upload_ctx->user_data);
#endif
		return;
	}

	enable_0copy(sock);

	if (param.options.report_interval_ms > 0) {
		uint32_t report_interval = param.options.report_interval_ms;
		uint32_t duration = param.duration_ms;

		/* Compute how many upload rounds will be executed and the duration
		 * of the last round when total duration isn't divisible by interval
		 */
		uint32_t rounds = (duration + report_interval - 1) / report_interval;
		uint32_t last_round_duration = duration - ((rounds - 1) * report_interval);

		struct zperf_results periodic_result;

		for (; rounds > 0; rounds--) {
			uint32_t round_duration;

			if (rounds == 1) {
				round_duration = last_round_duration;
			} else {
				round_duration = report_interval;
			}
			ret = tcp_upload(sock, round_duration, param.packet_size, &periodic_result);
			if (ret < 0) {
#ifdef CONFIG_SKADI_OS
        		skadi_perf_cancel();
				tcp_upload_cb(ZPERF_SESSION_ERROR, NULL, upload_ctx->user_data, upload_ctx->callback);
#else
				upload_ctx->callback(ZPERF_SESSION_ERROR, NULL,
							upload_ctx->user_data);
#endif
				goto cleanup;
			}
#ifdef CONFIG_SKADI_OS
{
			struct zperf_results *result_token = skadi_cap_ops_derive_arg(&periodic_result, sizeof(periodic_result));
			__ASSERT_NO_MSG(result_token);
			tcp_upload_cb(ZPERF_SESSION_PERIODIC_RESULT, result_token, upload_ctx->user_data, upload_ctx->callback);
			skadi_cap_ops_drop(result_token);
}
#else
			upload_ctx->callback(ZPERF_SESSION_PERIODIC_RESULT, &periodic_result,
						 upload_ctx->user_data);
#endif

			result.nb_packets_sent += periodic_result.nb_packets_sent;
			result.client_time_in_us += periodic_result.client_time_in_us;
			result.nb_packets_errors += periodic_result.nb_packets_errors;
		}

		result.packet_size = periodic_result.packet_size;

	} else {
		ret = tcp_upload(sock, param.duration_ms, param.packet_size, &result);
		if (ret < 0) {
#ifdef CONFIG_SKADI_OS
        	skadi_perf_cancel();
			tcp_upload_cb(ZPERF_SESSION_ERROR, NULL, upload_ctx->user_data, upload_ctx->callback);
#else
			upload_ctx->callback(ZPERF_SESSION_ERROR, NULL,
			     		 upload_ctx->user_data);
#endif
			goto cleanup;
		}
	}
#ifdef CONFIG_SKADI_OS
{	
	struct zperf_results *result_token = skadi_cap_ops_derive_arg(&result, sizeof(result));
	__ASSERT_NO_MSG(result_token);
    skadi_perf_cancel();
	tcp_upload_cb(ZPERF_SESSION_FINISHED, result_token, upload_ctx->user_data, upload_ctx->callback);
	skadi_cap_ops_drop(result_token);
}
#else
	upload_ctx->callback(ZPERF_SESSION_FINISHED, &result,
			     upload_ctx->user_data);
#endif
cleanup:
#ifdef CONFIG_SKADI_OS
	skadi_zsock_close(sock);
#else
	zsock_close(sock);
#endif
}
#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(tcp_upload_async_work)
#endif

int zperf_tcp_upload_async(const struct zperf_upload_params *param,
			   zperf_callback callback, void *user_data)
{
	if (param == NULL || callback == NULL) {
		return -EINVAL;
	}

#ifdef CONFIG_SKADI_OS
	if (skadi_work_is_pending(&tcp_async_upload_ctx.work)) {
		return -EBUSY;
	}

	skadi_subsystem_check_function_pointer(callback, false, false);

	skadi_perf_start(1000);
#else
	if (k_work_is_pending(&tcp_async_upload_ctx.work)) {
		return -EBUSY;
	}
#endif

	memcpy(&tcp_async_upload_ctx.param, param, sizeof(*param));
	tcp_async_upload_ctx.callback = callback;
	tcp_async_upload_ctx.user_data = user_data;

	zperf_async_work_submit(&tcp_async_upload_ctx.work);

	return 0;
}

#ifdef CONFIG_SKADI_OS
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_zperf_tcp_upload_async, const struct zperf_upload_params *param, zperf_callback callback, void *user_data)
		return zperf_tcp_upload_async(param, callback, user_data);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_zperf_tcp_upload_async)
#endif

void zperf_tcp_uploader_init(void)
{
#ifdef CONFIG_SKADI_OS
	skadi_work_init(&tcp_async_upload_ctx.work, SKADI_SUBSYSTEM_FUNCTION_POINTER(tcp_upload_async_work));
	tcp_async_upload_ctx.work.user_data = &tcp_async_upload_ctx;
#ifdef CONFIG_SKADI_NET_ZEROCOPY
	(void)arch_dcache_flush_range(sample_packet, sizeof(sample_packet));
	sample_packet_token = skadi_cap_ops_derive_arg_ro(sample_packet, sizeof(sample_packet));
	__ASSERT_NO_MSG(sample_packet_token);
#endif /* CONFIG_SKADI_NET_ZEROCOPY */
#else
	k_work_init(&tcp_async_upload_ctx.work, tcp_upload_async_work);
#endif
}
