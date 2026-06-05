/*
 * Copyright (c) 2016 Intel Corporation
 * Copyright (c) 2022 Nordic Semiconductor ASA
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file zperf.h
 *
 * @brief Zperf API
 * @defgroup zperf Zperf API
 * @since 3.3
 * @version 0.8.0
 * @ingroup networking
 * @{
 */

#ifndef SKADI_ZPERF_H
#define SKADI_ZPERF_H

#include <zephyr/net/zperf.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Synchronous UDP upload operation. The function blocks until the upload
 *        is complete.
 *
 * @param param Upload parameters.
 * @param result Session results.
 *
 * @return 0 if session completed successfully, a negative error code otherwise.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_udp_upload, const struct zperf_upload_params *param, struct zperf_results *result);

static inline int _skadi_zperf_udp_upload(const struct zperf_upload_params *param, struct zperf_results *result){
	const struct zperf_upload_params *param_token = param ? skadi_cap_ops_derive_arg_ro(param, sizeof(*param)) : param;
	struct zperf_results *result_token = result ? skadi_cap_ops_derive_arg(result, sizeof(*result)) : result;
	int ret;

	__ASSERT_NO_MSG(param_token);
	__ASSERT_NO_MSG(result_token);

	if(!param_token || !result_token){
		goto out;
	}

	ret = __skadi_zperf_udp_upload(param_token, result_token);
out:
	if(param_token){
		skadi_cap_ops_drop(param_token);
	}

	if(result_token){
		skadi_cap_ops_drop(result_token);
	}

	return ret;
}

#define skadi_zperf_udp_upload(PARAM, RESULT) _skadi_zperf_udp_upload(PARAM, RESULT)


/**
 * @brief Synchronous TCP upload operation. The function blocks until the upload
 *        is complete.
 *
 * @param param Upload parameters.
 * @param result Session results.
 *
 * @return 0 if session completed successfully, a negative error code otherwise.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_tcp_upload, const struct zperf_upload_params *param, struct zperf_results *result);

static inline int _skadi_zperf_tcp_upload(const struct zperf_upload_params *param, struct zperf_results *result){
	const struct zperf_upload_params *param_token = param ? skadi_cap_ops_derive_arg_ro(param, sizeof(*param)) : param;
	struct zperf_results *result_token = result ? skadi_cap_ops_derive_arg(result, sizeof(*result)) : result;
	int ret;

	__ASSERT_NO_MSG(param_token);
	__ASSERT_NO_MSG(result_token);

	if(!param_token || !result_token){
		goto out;
	}

	ret = __skadi_zperf_tcp_upload(param_token, result_token);
out:
	if(param_token){
		skadi_cap_ops_drop(param_token);
	}

	if(result_token){
		skadi_cap_ops_drop(result_token);
	}

	return ret;
}

#define skadi_zperf_tcp_upload(PARAM, RESULT) _skadi_zperf_tcp_upload(PARAM, RESULT)

/**
 * @brief Asynchronous UDP upload operation.
 *
 * @note Only one asynchronous upload can be performed at a time.
 *
 * @param param Upload parameters.
 * @param callback Session results callback.
 * @param user_data A pointer to the user data to be provided with the callback.
 *
 * @return 0 if session was scheduled successfully, a negative error code
 *         otherwise.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_udp_upload_async, const struct zperf_upload_params *param, zperf_callback callback, void *user_data);

static inline int _skadi_zperf_udp_upload_async(const struct zperf_upload_params *param, zperf_callback callback, void *user_data){
	const struct zperf_upload_params *param_token = param ? skadi_cap_ops_derive_arg_ro(param, sizeof(*param)) : param;
	int ret;

	__ASSERT_NO_MSG(param_token);

	if(!param_token){
		return -ENOMEM;
	}

	ret = __skadi_zperf_udp_upload_async(param_token, callback, user_data);

	if(param_token){
		skadi_cap_ops_drop(param_token);
	}

	return ret;
}

#define skadi_zperf_udp_upload_async(PARAM, CALLBACK, USER_DATA) _skadi_zperf_udp_upload_async(PARAM, CALLBACK, USER_DATA)


/**
 * @brief Asynchronous TCP upload operation.
 *
 * @note Only one asynchronous upload can be performed at a time.
 *
 * @param param Upload parameters.
 * @param callback Session results callback.
 * @param user_data A pointer to the user data to be provided with the callback.
 *
 * @return 0 if session was scheduled successfully, a negative error code
 *         otherwise.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_tcp_upload_async, const struct zperf_upload_params *param, zperf_callback callback, void *user_data);

static inline int _skadi_zperf_tcp_upload_async(const struct zperf_upload_params *param, zperf_callback callback, void *user_data){
	const struct zperf_upload_params *param_token = param ? skadi_cap_ops_derive_arg_ro(param, sizeof(*param)) : param;
	int ret;

	__ASSERT_NO_MSG(param_token);

	if(!param_token){
		return -ENOMEM;
	}

	ret = __skadi_zperf_tcp_upload_async(param_token, callback, user_data);

	if(param_token){
		skadi_cap_ops_drop(param_token);
	}

	return ret;
}

#define skadi_zperf_tcp_upload_async(PARAM, CALLBACK, USER_DATA) _skadi_zperf_tcp_upload_async(PARAM, CALLBACK, USER_DATA)


/**
 * @brief Start UDP server.
 *
 * @note Only one UDP server instance can run at a time.
 *
 * @param param Download parameters.
 * @param callback Session results callback.
 * @param user_data A pointer to the user data to be provided with the callback.
 *
 * @return 0 if server was started, a negative error code otherwise.
 */

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_udp_download, const struct zperf_download_params *param, zperf_callback callback, void *user_data);

static inline int _skadi_zperf_udp_download(const struct zperf_download_params *param, zperf_callback callback, void *user_data){
	const struct zperf_download_params *param_token = param ? skadi_cap_ops_derive_arg_ro(param, sizeof(*param)) : param;
	int ret;

	__ASSERT_NO_MSG(param_token);

	if(!param_token){
		return -ENOMEM;
	}

	ret = __skadi_zperf_udp_download(param_token, callback, user_data);

	if(param_token){
		skadi_cap_ops_drop(param_token);
	}

	return ret;
}

#define skadi_zperf_udp_download(PARAM, CALLBACK, USER_DATA) _skadi_zperf_udp_download(PARAM, CALLBACK, USER_DATA)

/**
 * @brief Start TCP server.
 *
 * @note Only one TCP server instance can run at a time.
 *
 * @param param Download parameters.
 * @param callback Session results callback.
 * @param user_data A pointer to the user data to be provided with the callback.
 *
 * @return 0 if server was started, a negative error code otherwise.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_tcp_download, const struct zperf_download_params *param, zperf_callback callback, void *user_data);

static inline int _skadi_zperf_tcp_download(const struct zperf_download_params *param, zperf_callback callback, void *user_data){
	const struct zperf_download_params *param_token = param ? skadi_cap_ops_derive_arg_ro(param, sizeof(*param)) : param;
	int ret;

	__ASSERT_NO_MSG(param_token);

	if(!param_token){
		return -ENOMEM;
	}

	ret = __skadi_zperf_tcp_download(param_token, callback, user_data);

	if(param_token){
		skadi_cap_ops_drop(param_token);
	}

	return ret;
}

#define skadi_zperf_tcp_download(PARAM, CALLBACK, USER_DATA) _skadi_zperf_tcp_download(PARAM, CALLBACK, USER_DATA)

/**
 * @brief Stop UDP server.
 *
 * @return 0 if server was stopped successfully, a negative error code otherwise.
 */

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_tcp_download_stop);

static inline int _skadi_zperf_tcp_download_stop(void){
	return __skadi_zperf_tcp_download_stop();
}

#define skadi_zperf_tcp_download_stop _skadi_zperf_tcp_download_stop


/**
 * @brief Stop TCP server.
 *
 * @return 0 if server was stopped successfully, a negative error code otherwise.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_zperf_udp_download_stop);

static inline int _skadi_zperf_udp_download_stop(void){
	return __skadi_zperf_udp_download_stop();
}

#define skadi_zperf_udp_download_stop _skadi_zperf_udp_download_stop

#ifdef __cplusplus
}
#endif

/**
 * @}
 */

#endif /* SKADI_ZPERF_H */
