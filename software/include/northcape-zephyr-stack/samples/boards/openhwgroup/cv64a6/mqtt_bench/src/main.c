/*
 * Copyright (c) 2017 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(net_mqtt_publisher_sample, LOG_LEVEL_DBG);

#include <zephyr/kernel.h>
#include <zephyr/net/socket.h>
#include <zephyr/net/mqtt.h>
#include <zephyr/random/random.h>
#include <zephyr/timing/timing.h>
#include <zephyr/sys_clock.h>


#ifdef SKADI_SUBSYSTEM
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/skadi_signal.h>
#include <zephyr/skadi/net/skadi_socket.h>
#include <zephyr/skadi/net/skadi_tls_credentials.h>
#include <zephyr/skadi/random/skadi_random.h>
#include <zephyr/skadi/arpa/skadi_inet.h>
#include <zephyr/skadi/subsystems/mqtt/skadi_mqtt.h>
#endif

#include <cv64a6.h>


#include <zephyr/skadi/skadi_benchmark.h>

#include <string.h>
#include <errno.h>

#include "config.h"

#if defined(CONFIG_USERSPACE)
#include <zephyr/app_memory/app_memdomain.h>
K_APPMEM_PARTITION_DEFINE(app_partition);
struct k_mem_domain app_domain;
#define APP_BMEM K_APP_BMEM(app_partition)
#define APP_DMEM K_APP_DMEM(app_partition)
#else
#define APP_BMEM
#define APP_DMEM
#endif

/* Buffers for MQTT client. */
static APP_BMEM uint8_t rx_buffer[APP_MQTT_BUFFER_SIZE];
static APP_BMEM uint8_t tx_buffer[APP_MQTT_BUFFER_SIZE];

#if defined(CONFIG_MQTT_LIB_WEBSOCKET)
/* Making RX buffer large enough that the full IPv6 packet can fit into it */
#define MQTT_LIB_WEBSOCKET_RECV_BUF_LEN 1280

/* Websocket needs temporary buffer to store partial packets */
static APP_BMEM uint8_t temp_ws_rx_buf[MQTT_LIB_WEBSOCKET_RECV_BUF_LEN];
#endif

/* The mqtt client struct */
static APP_BMEM struct mqtt_client client_ctx;

/* MQTT Broker details. */
static APP_BMEM struct sockaddr_storage broker;
#ifdef SKADI_SUBSYSTEM
static socklen_t broker_len;
#endif

#if defined(CONFIG_SOCKS)
static APP_BMEM struct sockaddr socks5_proxy;
#endif

#ifdef SKADI_SUBSYSTEM
static struct zsock_pollfd fds[1];
static struct pollfd *fds_token;
#else
static APP_BMEM struct pollfd fds[1];
#endif
static APP_BMEM int nfds;

static APP_BMEM bool connected;

#if defined(CONFIG_MQTT_LIB_TLS)

#include "test_certs.h"

#define TLS_SNI_HOSTNAME "foo.bar"
#define APP_CA_CERT_TAG 1
#define APP_PSK_TAG 2

static APP_DMEM sec_tag_t m_sec_tags[] = {
#if defined(MBEDTLS_X509_CRT_PARSE_C) || defined(CONFIG_NET_SOCKETS_OFFLOAD)
		APP_CA_CERT_TAG,
#endif
#if defined(MBEDTLS_KEY_EXCHANGE_SOME_PSK_ENABLED)
		APP_PSK_TAG,
#endif
};

static int tls_init(void)
{
	int err = -EINVAL;

#if defined(MBEDTLS_X509_CRT_PARSE_C) || defined(CONFIG_NET_SOCKETS_OFFLOAD)
#ifdef SKADI_SUBSYSTEM
	err = skadi_tls_credential_add(APP_CA_CERT_TAG, TLS_CREDENTIAL_CA_CERTIFICATE,
				 ca_certificate, sizeof(ca_certificate));
#else
	err = tls_credential_add(APP_CA_CERT_TAG, TLS_CREDENTIAL_CA_CERTIFICATE,
				 ca_certificate, sizeof(ca_certificate));
#endif /* SKADI_SUBSYSTEM */
	if (err < 0) {
		LOG_ERR("Failed to register public certificate: %d", err);
		return err;
	}
#endif

#if defined(MBEDTLS_KEY_EXCHANGE_SOME_PSK_ENABLED)
#ifdef SKADI_SUBSYSTEM
	err = skadi_tls_credential_add(APP_PSK_TAG, TLS_CREDENTIAL_PSK,
				 client_psk, sizeof(client_psk));
#else
	err = tls_credential_add(APP_PSK_TAG, TLS_CREDENTIAL_PSK,
				 client_psk, sizeof(client_psk));
#endif /* SKADI_SUBSYSTEM */
	if (err < 0) {
		LOG_ERR("Failed to register PSK: %d", err);
		return err;
	}

#ifdef SKADI_SUBSYSTEM
	err = skadi_tls_credential_add(APP_PSK_TAG, TLS_CREDENTIAL_PSK_ID,
				 client_psk_id, sizeof(client_psk_id) - 1);
#else
	err = tls_credential_add(APP_PSK_TAG, TLS_CREDENTIAL_PSK_ID,
				 client_psk_id, sizeof(client_psk_id) - 1);
#endif /* SKADI_SUBSYSTEM */
	if (err < 0) {
		LOG_ERR("Failed to register PSK ID: %d", err);
	}
#endif

	return err;
}

#endif /* CONFIG_MQTT_LIB_TLS */

static void prepare_fds(struct mqtt_client *client)
{
	if (client->transport.type == MQTT_TRANSPORT_NON_SECURE) {
		fds[0].fd = client->transport.tcp.sock;
	}
#if defined(CONFIG_MQTT_LIB_TLS)
	else if (client->transport.type == MQTT_TRANSPORT_SECURE) {
		fds[0].fd = client->transport.tls.sock;
	}
#endif

	fds[0].events = POLLIN;
	nfds = 1;
}

static void clear_fds(void)
{
	nfds = 0;
}


#define RC_STR(rc) ((rc) == 0 ? "OK" : "ERROR")

#define PRINT_RESULT(func, rc) \
	LOG_INF("%s: %d <%s>", (func), rc, RC_STR(rc))

static int wait(int timeout)
{
	int ret = 0;

	if (nfds > 0) {
#ifdef SKADI_SUBSYSTEM
		if(!fds_token){
			fds_token = skadi_cap_ops_derive_arg(fds, sizeof(fds));
		}
		__ASSERT_NO_MSG(fds_token);
		if(!fds_token){
			return -ENOMEM;
		}
		ret = skadi_zsock_poll(fds_token, nfds, timeout);
#else
		ARG_UNUSED(timeout);
		ret = poll(fds, nfds, 0);
#endif
		if (ret < 0) {
			LOG_ERR("poll error: %d", errno);
		}
	}

	return ret;
}

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, mqtt_evt_handler, struct mqtt_client *const client, const struct mqtt_evt *evt)
#else
void mqtt_evt_handler(struct mqtt_client *const client,
		      const struct mqtt_evt *evt)
#endif
{
	int err;

	switch (evt->type) {
	case MQTT_EVT_CONNACK:
		if (evt->result != 0) {
			LOG_ERR("MQTT connect failed %d", evt->result);
			break;
		}

		connected = true;
		LOG_INF("MQTT client connected!");

		break;

	case MQTT_EVT_DISCONNECT:
		LOG_INF("MQTT client disconnected %d", evt->result);

		connected = false;
		clear_fds();

		break;

	case MQTT_EVT_PUBACK:
		if (evt->result != 0) {
			LOG_ERR("MQTT PUBACK error %d", evt->result);
			break;
		}

		LOG_INF("PUBACK packet id: %u", evt->param.puback.message_id);

		break;

	case MQTT_EVT_PUBREC:
		if (evt->result != 0) {
			LOG_ERR("MQTT PUBREC error %d", evt->result);
			break;
		}

		LOG_INF("PUBREC packet id: %u", evt->param.pubrec.message_id);

		const struct mqtt_pubrel_param rel_param = {
			.message_id = evt->param.pubrec.message_id
		};

#ifdef SKADI_SUBSYSTEM
		err = skadi_mqtt_publish_qos2_release(client, &rel_param);
#else
		err = mqtt_publish_qos2_release(client, &rel_param);
#endif
		if (err != 0) {
			LOG_ERR("Failed to send MQTT PUBREL: %d", err);
		}

		break;

	case MQTT_EVT_PUBCOMP:
		if (evt->result != 0) {
			LOG_ERR("MQTT PUBCOMP error %d", evt->result);
			break;
		}

		LOG_INF("PUBCOMP packet id: %u",
			evt->param.pubcomp.message_id);

		break;

	case MQTT_EVT_PINGRESP:
		LOG_INF("PINGRESP packet");
		break;

	default:
		break;
	}
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(mqtt_evt_handler)
#endif

static char *get_mqtt_payload(enum mqtt_qos qos)
{
#if APP_BLUEMIX_TOPIC
	static APP_BMEM char payload[30];
#ifdef SKADI_SUBSYSTEM
	snprintk(payload, sizeof(payload), "{d:{temperature:%d}}",
		 skadi_sys_rand8_get());
#else
	snprintk(payload, sizeof(payload), "{d:{temperature:%d}}",
		 sys_rand8_get());
#endif
#else
	static APP_DMEM char payload[] = "DOORS:OPEN_QoSx";

	payload[strlen(payload) - 1] = '0' + qos;
#endif

	return payload;
}

static char *get_mqtt_topic(void)
{
#if APP_BLUEMIX_TOPIC
	return "iot-2/type/"BLUEMIX_DEVTYPE"/id/"BLUEMIX_DEVID
	       "/evt/"BLUEMIX_EVENT"/fmt/"BLUEMIX_FORMAT;
#else
	return "sensors";
#endif
}

static int publish(struct mqtt_client *client, enum mqtt_qos qos)
{
	struct mqtt_publish_param param;

	param.message.topic.qos = qos;
	param.message.topic.topic.utf8 = (uint8_t *)get_mqtt_topic();
	param.message.topic.topic.size =
			strlen(param.message.topic.topic.utf8);
	param.message.payload.data = get_mqtt_payload(qos);
	param.message.payload.len =
			strlen(param.message.payload.data);
#ifdef SKADI_SUBSYSTEM
	param.message_id = skadi_sys_rand16_get();
#else
	param.message_id = sys_rand16_get();
#endif
	param.dup_flag = 0U;
	param.retain_flag = 0U;
#ifdef SKADI_SUBSYSTEM
	return skadi_mqtt_publish(client, &param);
#else
	return mqtt_publish(client, &param);
#endif
}

static void broker_init(void)
{
#if defined(CONFIG_NET_IPV6)
	struct sockaddr_in6 *broker6 = (struct sockaddr_in6 *)&broker;

	broker6->sin6_family = AF_INET6;
	broker6->sin6_port = htons(SERVER_PORT);
#ifdef SKADI_SUBSYSTEM
	skadi_inet_pton(AF_INET6, SERVER_ADDR, &broker6->sin6_addr);
	broker_len = sizeof(struct sockaddr_in6);
#else
	inet_pton(AF_INET6, SERVER_ADDR, &broker6->sin6_addr);
#endif /* SKADI_SUBSYSTEM */

#if defined(CONFIG_SOCKS)
	struct sockaddr_in6 *proxy6 = (struct sockaddr_in6 *)&socks5_proxy;

	proxy6->sin6_family = AF_INET6;
	proxy6->sin6_port = htons(SOCKS5_PROXY_PORT);
#ifdef SKADI_SUBSYSTEM
	skadi_inet_pton(AF_INET6, SOCKS5_PROXY_ADDR, &proxy6->sin6_addr);
#else
	inet_pton(AF_INET6, SOCKS5_PROXY_ADDR, &proxy6->sin6_addr);
#endif /* SKADI_SUBSYSTEM */
#endif
#else
	struct sockaddr_in *broker4 = (struct sockaddr_in *)&broker;

	broker4->sin_family = AF_INET;
	broker4->sin_port = htons(SERVER_PORT);
#ifdef SKADI_SUBSYSTEM
	skadi_inet_pton(AF_INET, SERVER_ADDR, &broker4->sin_addr);
	broker_len = sizeof(struct sockaddr_in);
#else
	inet_pton(AF_INET, SERVER_ADDR, &broker4->sin_addr);
#endif /* SKADI_SUBSYSTEM */
#if defined(CONFIG_SOCKS)
	struct sockaddr_in *proxy4 = (struct sockaddr_in *)&socks5_proxy;

	proxy4->sin_family = AF_INET;
	proxy4->sin_port = htons(SOCKS5_PROXY_PORT);
#ifdef SKADI_SUBSYSTEM
	skadi_inet_pton(AF_INET, SOCKS5_PROXY_ADDR, &proxy4->sin_addr);
	broker_len = sizeof(struct sockaddr_in);
#else
	inet_pton(AF_INET, SOCKS5_PROXY_ADDR, &proxy4->sin_addr);
#endif /* SKADI_SUBSYSTEM */
#endif
#endif
}

static struct mqtt_utf8 mqtt_user, mqtt_password;

static void client_init(struct mqtt_client *client)
{
#ifdef SKADI_SUBSYSTEM
	skadi_mqtt_client_init(client);
#else
	mqtt_client_init(client);
#endif

	broker_init();

	mqtt_user.utf8 = (uint8_t *)MQTT_USER;
	mqtt_user.size = strlen(MQTT_USER);

	mqtt_password.utf8 = (uint8_t *)MQTT_PASSWORD;
	mqtt_password.size = strlen(MQTT_PASSWORD);

	
#ifdef SKADI_SUBSYSTEM
	__ASSERT_NO_MSG(broker_len);
	client->broker = skadi_cap_ops_derive_arg(&broker, broker_len);
	__ASSERT_NO_MSG(client->broker);
	client->evt_cb = SKADI_SUBSYSTEM_FUNCTION_POINTER(mqtt_evt_handler);
#else
	/* MQTT client configuration */
	client->broker = &broker;
	client->evt_cb = mqtt_evt_handler;
#endif
	client->client_id.utf8 = (uint8_t *)MQTT_CLIENTID;
	client->client_id.size = strlen(MQTT_CLIENTID);
	client->password = &mqtt_password;
	client->user_name = &mqtt_user;
	client->protocol_version = MQTT_VERSION_3_1_1;

	/* MQTT buffers configuration */
	client->rx_buf = rx_buffer;
	client->rx_buf_size = sizeof(rx_buffer);
	client->tx_buf = tx_buffer;
	client->tx_buf_size = sizeof(tx_buffer);

	/* MQTT transport configuration */
#if defined(CONFIG_MQTT_LIB_TLS)
#if defined(CONFIG_MQTT_LIB_WEBSOCKET)
	client->transport.type = MQTT_TRANSPORT_SECURE_WEBSOCKET;
#else
	client->transport.type = MQTT_TRANSPORT_SECURE;
#endif

	struct mqtt_sec_config *tls_config = &client->transport.tls.config;

	tls_config->peer_verify = TLS_PEER_VERIFY_REQUIRED;
	tls_config->cipher_list = NULL;
	tls_config->sec_tag_list = m_sec_tags;
	tls_config->sec_tag_count = ARRAY_SIZE(m_sec_tags);
#if defined(MBEDTLS_X509_CRT_PARSE_C) || defined(CONFIG_NET_SOCKETS_OFFLOAD)
	tls_config->hostname = TLS_SNI_HOSTNAME;
#else
	tls_config->hostname = NULL;
#endif

#else
#if defined(CONFIG_MQTT_LIB_WEBSOCKET)
	client->transport.type = MQTT_TRANSPORT_NON_SECURE_WEBSOCKET;
#else
	client->transport.type = MQTT_TRANSPORT_NON_SECURE;
#endif
#endif

#if defined(CONFIG_MQTT_LIB_WEBSOCKET)
	client->transport.websocket.config.host = SERVER_ADDR;
	client->transport.websocket.config.url = "/mqtt";
	client->transport.websocket.config.tmp_buf = temp_ws_rx_buf;
	client->transport.websocket.config.tmp_buf_len =
						sizeof(temp_ws_rx_buf);
	client->transport.websocket.timeout = 5 * MSEC_PER_SEC;
#endif

#if defined(CONFIG_SOCKS)
	mqtt_client_set_proxy(client, &socks5_proxy,
			      socks5_proxy.sa_family == AF_INET ?
			      sizeof(struct sockaddr_in) :
			      sizeof(struct sockaddr_in6));
#endif
}

/* In this routine we block until the connected variable is 1 */
static int try_to_connect(struct mqtt_client *client)
{
	int rc, i = 0;

	while (i++ < APP_CONNECT_TRIES && !connected) {

		client_init(client);
#ifdef SKADI_SUBSYSTEM
		rc = skadi_mqtt_connect(client);
#else
		rc = mqtt_connect(client);
#endif
		if (rc != 0) {
			PRINT_RESULT("mqtt_connect", rc);
#ifdef SKADI_SUBSYSTEM
			skadi_sleep(K_MSEC(APP_SLEEP_MSECS));
#else
			k_sleep(K_MSEC(APP_SLEEP_MSECS));
#endif
			continue;
		}

		prepare_fds(client);

		if (wait(APP_CONNECT_TIMEOUT_MS)) {
#ifdef SKADI_SUBSYSTEM
			skadi_mqtt_input(client);
#else
			mqtt_input(client);
#endif
		}

		if (!connected) {
			LOG_INF("Not connected after %d MS!", APP_CONNECT_TIMEOUT_MS);
#ifdef SKADI_SUBSYSTEM
			skadi_mqtt_abort(client);
#else
			mqtt_abort(client);
#endif
		}
	}

	if (connected) {
		return 0;
	}

	return -EINVAL;
}

static int process_mqtt_and_sleep(struct mqtt_client *client, int timeout)
{
	int64_t remaining = timeout;
#ifdef SKADI_SUBSYSTEM
	int64_t start_time = skadi_uptime_get();
#else
	int64_t start_time = k_uptime_get();
#endif
	int rc;

	while (remaining > 0 && connected) {
		if (wait(remaining)) {
#ifdef SKADI_SUBSYSTEM
			rc = skadi_mqtt_input(client);
#else
			rc = mqtt_input(client);
#endif
			if (rc != 0) {
				PRINT_RESULT("mqtt_input", rc);
				return rc;
			}
		}

#ifdef SKADI_SUBSYSTEM
		rc = skadi_mqtt_live(client);
#else
		rc = mqtt_live(client);
#endif
		if (rc != 0 && rc != -EAGAIN) {
			PRINT_RESULT("mqtt_live", rc);
			return rc;
		} else if (rc == 0) {
#ifdef SKADI_SUBSYSTEM
			rc = skadi_mqtt_input(client);
#else
			rc = mqtt_input(client);
#endif
			if (rc != 0) {
				PRINT_RESULT("mqtt_input", rc);
				return rc;
			}
		}
#ifdef SKADI_SUBSYSTEM
		remaining = timeout + start_time - skadi_uptime_get();
#else
		remaining = timeout + start_time - k_uptime_get();
#endif
	}

	return 0;
}

#define SUCCESS_OR_EXIT(rc) { if (rc != 0) { return 1; } }
/* continue in loop - will try to re-establish a failed connection */
#define SUCCESS_OR_CONTINUE(rc) { if (rc != 0) { continue; } }

static struct skadi_benchmark_state timing_samples[CONFIG_NET_SAMPLE_APP_MAX_ITERATIONS];

static int publisher(void)
{
	int rc, r = 0;
	size_t collected_samples = 0;


	timing_start();

	skadi_perf_start(1000);

	while (collected_samples < CONFIG_NET_SAMPLE_APP_MAX_ITERATIONS) {
		timing_t start_val, end_val;
		int64_t duration;
		r = -1;

		/* tolerate loss of connection in run */
		if(!connected){
			rc = try_to_connect(&client_ctx);
			PRINT_RESULT("try_to_connect", rc);
			SUCCESS_OR_CONTINUE(rc);
		}

		skadi_benchmark_prepare_sample(&timing_samples[collected_samples]);

		start_val = timing_counter_get();

#ifdef SKADI_SUBSYSTEM
		rc = skadi_mqtt_ping(&client_ctx);
#else
		rc = mqtt_ping(&client_ctx);
#endif
		PRINT_RESULT("mqtt_ping", rc);
		SUCCESS_OR_CONTINUE(rc);

		rc = process_mqtt_and_sleep(&client_ctx, APP_SLEEP_MSECS);
		SUCCESS_OR_CONTINUE(rc);

		rc = publish(&client_ctx, MQTT_QOS_0_AT_MOST_ONCE);
		PRINT_RESULT("mqtt_publish", rc);
		SUCCESS_OR_CONTINUE(rc);

		rc = process_mqtt_and_sleep(&client_ctx, APP_SLEEP_MSECS);
		SUCCESS_OR_CONTINUE(rc);

		rc = publish(&client_ctx, MQTT_QOS_1_AT_LEAST_ONCE);
		PRINT_RESULT("mqtt_publish", rc);
		SUCCESS_OR_CONTINUE(rc);

		rc = process_mqtt_and_sleep(&client_ctx, APP_SLEEP_MSECS);
		SUCCESS_OR_CONTINUE(rc);

		rc = publish(&client_ctx, MQTT_QOS_2_EXACTLY_ONCE);
		PRINT_RESULT("mqtt_publish", rc);
		SUCCESS_OR_CONTINUE(rc);

		rc = process_mqtt_and_sleep(&client_ctx, APP_SLEEP_MSECS);
		SUCCESS_OR_CONTINUE(rc);

		end_val = timing_counter_get();

		duration =  timing_cycles_get(&start_val, &end_val);
		duration = timing_cycles_to_ns(duration);
		
		skadi_benchmark_add_sample(&timing_samples[collected_samples], duration);

		LOG_INF("Iteration %zu duration %"PRId64" ns (start: %"PRIu64" end: %"PRIu64")!", (collected_samples+1), duration, start_val, end_val);

		r = 0;

		collected_samples ++;
	}
	skadi_perf_cancel();


	timing_stop();

#ifdef SKADI_SUBSYSTEM
	rc = skadi_mqtt_disconnect(&client_ctx);
#else
	rc = mqtt_disconnect(&client_ctx);
#endif
	PRINT_RESULT("mqtt_disconnect", rc);

	skadi_benchmark_evaluate_samples(timing_samples, collected_samples, CONFIG_NET_SAMPLE_APP_MAX_ITERATIONS - collected_samples, "MQTT iteration times");

	z_cv64a6_finish_test(CONFIG_NET_SAMPLE_APP_MAX_ITERATIONS - collected_samples);

	LOG_INF("Bye!");

	return r;
}

static int start_app(void)
{
	int r = 0, i = 0;

/* wait for network link to stabilize */
#ifdef SKADI_SUBSYSTEM
	skadi_sleep(K_MSEC(10000));
#endif

	while (!CONFIG_NET_SAMPLE_APP_MAX_CONNECTIONS ||
	       i++ < CONFIG_NET_SAMPLE_APP_MAX_CONNECTIONS) {
		r = publisher();

		if (!CONFIG_NET_SAMPLE_APP_MAX_CONNECTIONS) {
#ifdef SKADI_SUBSYSTEM
			skadi_sleep(K_MSEC(5000));
#else
			k_sleep(K_MSEC(5000));
#endif
		}
	}

	return r;
}

#if defined(CONFIG_USERSPACE)
#define STACK_SIZE 2048

#if defined(CONFIG_NET_TC_THREAD_COOPERATIVE)
#define THREAD_PRIORITY K_PRIO_COOP(CONFIG_NUM_COOP_PRIORITIES - 1)
#else
#define THREAD_PRIORITY K_PRIO_PREEMPT(8)
#endif

K_THREAD_DEFINE(app_thread, STACK_SIZE,
		start_app, NULL, NULL, NULL,
		THREAD_PRIORITY, K_USER, -1);

static K_HEAP_DEFINE(app_mem_pool, 1024 * 2);
#endif

#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_MAIN(void)
#else
int main(void)
#endif
{
#if defined(CONFIG_MQTT_LIB_TLS)
	int rc;

	rc = tls_init();
	PRINT_RESULT("tls_init", rc);
#endif

#if defined(CONFIG_USERSPACE)
	int ret;

	struct k_mem_partition *parts[] = {
#if Z_LIBC_PARTITION_EXISTS
		&z_libc_partition,
#endif
		&app_partition
	};

	ret = k_mem_domain_init(&app_domain, ARRAY_SIZE(parts), parts);
	__ASSERT(ret == 0, "k_mem_domain_init() failed %d", ret);
	ARG_UNUSED(ret);

	k_mem_domain_add_thread(&app_domain, app_thread);
	k_thread_heap_assign(app_thread, &app_mem_pool);

	k_thread_start(app_thread);
	k_thread_join(app_thread, K_FOREVER);
#else
	exit(start_app());
#endif
	return 0;
}
#ifdef SKADI_SUBSYSTEM
SKADI_SUBSYSTEM_MAIN_END
#endif
