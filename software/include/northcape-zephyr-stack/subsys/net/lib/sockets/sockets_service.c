/*
 * Copyright (c) 2023 Nordic Semiconductor ASA
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(net_sock_svc, CONFIG_NET_SOCKETS_LOG_LEVEL);

#include <zephyr/kernel.h>
#include <zephyr/init.h>
#include <zephyr/net/socket_service.h>
#include <zephyr/zvfs/eventfd.h>

#ifdef CONFIG_SKADI_OS
#include <zephyr/skadi/skadi_mutex.h>
#include <zephyr/skadi/skadi_condvar.h>
#include <zephyr/skadi/sys/skadi_fdtable.h>
#include <zephyr/skadi/zvfs/skadi_eventfd.h>
#include <zephyr/skadi/skadi_sched.h>
#endif

static int init_socket_service(void);

enum SOCKET_SERVICE_THREAD_STATUS {
	SOCKET_SERVICE_THREAD_UNINITIALIZED = 0,
	SOCKET_SERVICE_THREAD_FAILED,
	SOCKET_SERVICE_THREAD_STOPPED,
	SOCKET_SERVICE_THREAD_RUNNING,
};
static enum SOCKET_SERVICE_THREAD_STATUS thread_status;

static K_MUTEX_DEFINE(lock);
static K_CONDVAR_DEFINE(wait_start);

#ifdef CONFIG_SKADI_OS
	static bool skadi_sockets_service_init_mutex_condvar(void){
		bool ret = true;
		ret = ret && skadi_mutex_init(&lock) == 0;
		ret = ret && skadi_condvar_init(&wait_start) == 0;

		return ret;
	}

	SKADI_SUBSYSTEM_INIT_FUNCTIONS(skadi_sockets_service_init_mutex_condvar);

	static sys_dlist_t skadi_socket_services = SYS_DLIST_STATIC_INIT(&skadi_socket_services);

	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(skadi_socket_service_callback, struct k_work *work);
#else

STRUCT_SECTION_START_EXTERN(net_socket_service_desc);
STRUCT_SECTION_END_EXTERN(net_socket_service_desc);

#endif

static struct service {
	struct zsock_pollfd events[CONFIG_NET_SOCKETS_POLL_MAX];
	int count;
} ctx;

#define get_idx(svc) (*(svc->idx))

void net_socket_service_foreach(net_socket_service_cb_t cb, void *user_data)
{
#ifdef CONFIG_SKADI_OS
	struct net_socket_service_desc *svc;
	SYS_DLIST_FOR_EACH_CONTAINER(&skadi_socket_services, svc, list_node){
#else
	STRUCT_SECTION_FOREACH(net_socket_service_desc, svc) {
#endif
		cb(svc, user_data);
	}
}

static void cleanup_svc_events(const struct net_socket_service_desc *svc)
{
	for (int i = 0; i < svc->pev_len; i++) {
		svc->pev[i].event.fd = -1;
		svc->pev[i].event.events = 0;
	}
}

int z_impl_net_socket_service_register(struct net_socket_service_desc *svc,
				       struct zsock_pollfd *fds, int len,
				       void *user_data)
{
	int i, ret = -ENOENT;

#ifdef CONFIG_SKADI_OS
	skadi_mutex_lock(&lock, K_FOREVER);
#else
	k_mutex_lock(&lock, K_FOREVER);
#endif

	if (thread_status == SOCKET_SERVICE_THREAD_UNINITIALIZED) {
#ifdef CONFIG_SKADI_OS
		(void)skadi_condvar_wait(&wait_start, &lock, K_FOREVER);
#else
		(void)k_condvar_wait(&wait_start, &lock, K_FOREVER);
#endif
	} else if (thread_status != SOCKET_SERVICE_THREAD_RUNNING) {
		NET_ERR("Socket service thread not running, service %p register fails.", svc);
		ret = -EIO;
		goto out;
	}

#ifndef CONFIG_SKADI_OS
	if (STRUCT_SECTION_START(net_socket_service_desc) > svc ||
	    STRUCT_SECTION_END(net_socket_service_desc) <= svc) {
		goto out;
	}
#endif

	if (fds == NULL) {
		cleanup_svc_events(svc);
#ifdef CONFIG_SKADI_OS
		__ASSERT_NO_MSG(sys_dnode_is_linked(&svc->list_node));
		sys_dlist_remove(&svc->list_node);
#endif
	} else {
		if (len > svc->pev_len) {
			NET_DBG("Too many file descriptors, "
				"max is %d for service %p",
				svc->pev_len, svc);
			ret = -ENOMEM;
			goto out;
		}

#ifdef CONFIG_SKADI_OS
		// do not add again if already part of the list
		if(!sys_dnode_is_linked(&svc->list_node)){
			sys_dlist_append(&skadi_socket_services, &svc->list_node);
		}
#endif

		for (i = 0; i < len; i++) {
			svc->pev[i].event = fds[i];
			svc->pev[i].user_data = user_data;
		}
	}

	/* Tell the thread to re-read the variables */
#ifdef CONFIG_SKADI_OS
	skadi_zvfs_eventfd_write(ctx.events[0].fd, 1);
#else
	zvfs_eventfd_write(ctx.events[0].fd, 1);
#endif
	ret = 0;

out:
#ifdef CONFIG_SKADI_OS
	skadi_mutex_unlock(&lock);
#else
	k_mutex_unlock(&lock);
#endif

	return ret;
}

#ifdef CONFIG_SKADI_OS
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_net_socket_service_register, struct net_socket_service_desc *svc, struct zsock_pollfd *fds, int len, void *user_data)
		return net_socket_service_register(svc, fds, len, user_data);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_net_socket_service_register)
#endif

static struct net_socket_service_desc *find_svc_and_event(
	struct zsock_pollfd *pev,
	struct net_socket_service_event **event)
{
#ifdef CONFIG_SKADI_OS
	struct net_socket_service_desc *svc;
	SYS_DLIST_FOR_EACH_CONTAINER(&skadi_socket_services, svc, list_node){
#else
	STRUCT_SECTION_FOREACH(net_socket_service_desc, svc) {
#endif
		for (int i = 0; i < svc->pev_len; i++) {
			if (svc->pev[i].event.fd == pev->fd) {
				*event = &svc->pev[i];
				return svc;
			}
		}
	}

	return NULL;
}

/* We do not set the user callback to our work struct because we need to
 * hook into the flow and restore the global poll array so that the next poll
 * round will not notice it and call the callback again while we are
 * servicing the callback.
 */
void net_socket_service_callback(struct k_work *work)
{
	struct net_socket_service_event *pev =
		CONTAINER_OF(work, struct net_socket_service_event, work);
	struct net_socket_service_desc *svc = pev->svc;
	struct net_socket_service_event ev = *pev;

#ifdef CONFIG_SKADI_OS
	struct net_socket_service_event *ev_token = skadi_cap_ops_derive_arg(&ev, sizeof(ev));
	__ASSERT_NO_MSG(ev.callback);
	__ASSERT_NO_MSG(ev_token);
	if(!ev_token){
		return;
	}
	skadi_subsystem_check_function_pointer(ev.callback, false, true);
	skadi_socket_service_callback(&ev_token->work, ev.callback);
	skadi_cap_ops_drop(ev_token);
#else
	ev.callback(&ev.work);
#endif

	/* Copy back the socket fd to the global array because we marked
	 * it as -1 when triggering the work.
	 */
	for (int i = 0; i < svc->pev_len; i++) {
		ctx.events[get_idx(svc) + i] = svc->pev[i].event;
	}
}

static int call_work(struct zsock_pollfd *pev, struct k_work_q *work_q,
		     struct k_work *work)
{
	int ret = 0;

	/* Mark the global fd non pollable so that we do not
	 * call the callback second time.
	 */
	pev->fd = -1;

	/* Synchronous call */
	net_socket_service_callback(work);

	return ret;

}

static int trigger_work(struct zsock_pollfd *pev)
{
	struct net_socket_service_event *event;
	struct net_socket_service_desc *svc;

	svc = find_svc_and_event(pev, &event);
	if (svc == NULL) {
		return -ENOENT;
	}

	event->svc = svc;

	/* Copy the triggered event to our event so that we know what
	 * was actually causing the event.
	 */
	event->event = *pev;

	return call_work(pev, svc->work_q, &event->work);
}

#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, socket_service_thread, void *p1, void *p2, void *p3)
{
	int ret, i, fd, count;
	zvfs_eventfd_t value;
	struct net_socket_service_desc *svc;
	struct zsock_pollfd *event_token = skadi_cap_ops_derive_arg(ctx.events, sizeof(ctx.events));

	__ASSERT_NO_MSG(event_token);

	ARG_UNUSED(p1);
	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	/* Create an zvfs_eventfd that can be used to trigger events during polling */
	fd = skadi_zvfs_eventfd(0, 0);
	if (fd < 0) {
		fd = -errno;
		NET_ERR("zvfs_eventfd failed (%d)", fd);
		goto out;
	}
/* as the services are dynamic, we have to re-start by initializing the event array again... */
restart:
	count = 0;

	/* Create contiguous poll event array to enable socket polling */
	SYS_DLIST_FOR_EACH_CONTAINER(&skadi_socket_services, svc, list_node) {
		NET_DBG("Service %s has %d pollable sockets",
			COND_CODE_1(CONFIG_NET_SOCKETS_LOG_LEVEL_DBG,
				    (svc->owner), ("")),
			svc->pev_len);
		get_idx(svc) = count + 1;
		count += svc->pev_len;
	}

	if ((count + 1) > ARRAY_SIZE(ctx.events)) {
		NET_ERR("You have %d services to monitor but "
			"%zd poll entries configured.",
			count + 1, ARRAY_SIZE(ctx.events));
		NET_ERR("Please increase value of %s to at least %d",
			"CONFIG_NET_SOCKETS_POLL_MAX", count + 1);
		goto fail;
	}

	NET_DBG("Monitoring %d socket entries", count);

	ctx.count = count + 1;

	thread_status = SOCKET_SERVICE_THREAD_RUNNING;
	skadi_condvar_broadcast(&wait_start);

	ctx.events[0].fd = fd;
	ctx.events[0].events = ZSOCK_POLLIN;

	i = 1;

	skadi_mutex_lock(&lock, K_FOREVER);

	/* Copy individual events to the big array */
	SYS_DLIST_FOR_EACH_CONTAINER(&skadi_socket_services, svc, list_node) {
		for (int j = 0; j < svc->pev_len; j++) {
			ctx.events[get_idx(svc) + j] = svc->pev[j].event;
		}
	}

	skadi_mutex_unlock(&lock);

	while (true) {
		ret = zsock_poll(event_token, count + 1, -1);
		if (ret < 0) {
			ret = -errno;
			NET_ERR("poll failed (%d)", ret);
			goto out;
		}

		if (ret == 0) {
			/* should not happen because timeout is -1 */
			break;
		}

		if (ret > 0 && ctx.events[0].revents) {
			skadi_zvfs_eventfd_read(ctx.events[0].fd, &value);
			NET_DBG("Received restart event.");
			goto restart;
		}

		for (i = 1; i < (count + 1); i++) {
			if (ctx.events[i].fd < 0) {
				continue;
			}

			if (ctx.events[i].revents > 0) {
				ret = trigger_work(&ctx.events[i]);
				if (ret < 0) {
					NET_DBG("Triggering work failed (%d)", ret);
				}
			}
		}
	}

out:
	NET_DBG("Socket service thread stopped");
	thread_status = SOCKET_SERVICE_THREAD_STOPPED;

	return;

fail:
	thread_status = SOCKET_SERVICE_THREAD_FAILED;
	skadi_condvar_broadcast(&wait_start);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(socket_service_thread)
#else
static void socket_service_thread(void)
{
	int ret, i, fd, count = 0;
	zvfs_eventfd_t value;

	STRUCT_SECTION_COUNT(net_socket_service_desc, &ret);
	if (ret == 0) {
		NET_INFO("No socket services found, service disabled.");
		goto fail;
	}

	/* Create contiguous poll event array to enable socket polling */
	STRUCT_SECTION_FOREACH(net_socket_service_desc, svc) {
		NET_DBG("Service %s has %d pollable sockets",
			COND_CODE_1(CONFIG_NET_SOCKETS_LOG_LEVEL_DBG,
				    (svc->owner), ("")),
			svc->pev_len);
		get_idx(svc) = count + 1;
		count += svc->pev_len;
	}

	if ((count + 1) > ARRAY_SIZE(ctx.events)) {
		NET_ERR("You have %d services to monitor but "
			"%zd poll entries configured.",
			count + 1, ARRAY_SIZE(ctx.events));
		NET_ERR("Please increase value of %s to at least %d",
			"CONFIG_NET_SOCKETS_POLL_MAX", count + 1);
		goto fail;
	}

	NET_DBG("Monitoring %d socket entries", count);

	ctx.count = count + 1;

	/* Create an zvfs_eventfd that can be used to trigger events during polling */
	fd = zvfs_eventfd(0, 0);
	if (fd < 0) {
		fd = -errno;
		NET_ERR("zvfs_eventfd failed (%d)", fd);
		goto out;
	}

	thread_status = SOCKET_SERVICE_THREAD_RUNNING;
	k_condvar_broadcast(&wait_start);

	ctx.events[0].fd = fd;
	ctx.events[0].events = ZSOCK_POLLIN;

restart:
	i = 1;

	k_mutex_lock(&lock, K_FOREVER);

	/* Copy individual events to the big array */
	STRUCT_SECTION_FOREACH(net_socket_service_desc, svc) {
		for (int j = 0; j < svc->pev_len; j++) {
			ctx.events[get_idx(svc) + j] = svc->pev[j].event;
		}
	}

	k_mutex_unlock(&lock);

	while (true) {
		ret = zsock_poll(ctx.events, count + 1, -1);
		if (ret < 0) {
			ret = -errno;
			NET_ERR("poll failed (%d)", ret);
			goto out;
		}

		if (ret == 0) {
			/* should not happen because timeout is -1 */
			break;
		}

		if (ret > 0 && ctx.events[0].revents) {
			zvfs_eventfd_read(ctx.events[0].fd, &value);
			NET_DBG("Received restart event.");
			goto restart;
		}

		for (i = 1; i < (count + 1); i++) {
			if (ctx.events[i].fd < 0) {
				continue;
			}

			if (ctx.events[i].revents > 0) {
				ret = trigger_work(&ctx.events[i]);
				if (ret < 0) {
					NET_DBG("Triggering work failed (%d)", ret);
				}
			}
		}
	}

out:
	NET_DBG("Socket service thread stopped");
	thread_status = SOCKET_SERVICE_THREAD_STOPPED;

	return;

fail:
	thread_status = SOCKET_SERVICE_THREAD_FAILED;
	k_condvar_broadcast(&wait_start);
}
#endif

#ifdef CONFIG_SKADI_OS
	static int init_socket_service(void)
{
	k_tid_t ssm;
	static struct k_thread service_thread;
	struct skadi_thread_create_params params;
	static K_THREAD_STACK_DEFINE(service_thread_stack,
				     CONFIG_NET_SOCKETS_SERVICE_STACK_SIZE);

	params.new_thread = &service_thread;
	params.stack = service_thread_stack;
	params.stack_size = K_THREAD_STACK_SIZEOF(service_thread_stack);
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(socket_service_thread);
	params.p1 = params.p2 = params.p3 = NULL;
	params.prio = CLAMP(CONFIG_NET_SOCKETS_SERVICE_THREAD_PRIO,
				    K_HIGHEST_APPLICATION_THREAD_PRIO,
				    K_LOWEST_APPLICATION_THREAD_PRIO);
	params.options = 0;
	params.delay = K_NO_WAIT;

	ssm = skadi_thread_create(&params);

	skadi_thread_name_set(ssm, "net_socket_service");

	return 0;
}
#else
static int init_socket_service(void)
{
	k_tid_t ssm;
	static struct k_thread service_thread;

	static K_THREAD_STACK_DEFINE(service_thread_stack,
				     CONFIG_NET_SOCKETS_SERVICE_STACK_SIZE);

	ssm = k_thread_create(&service_thread,
			      service_thread_stack,
			      K_THREAD_STACK_SIZEOF(service_thread_stack),
			      (k_thread_entry_t)socket_service_thread, NULL, NULL, NULL,
			      CLAMP(CONFIG_NET_SOCKETS_SERVICE_THREAD_PRIO,
				    K_HIGHEST_APPLICATION_THREAD_PRIO,
				    K_LOWEST_APPLICATION_THREAD_PRIO), 0, K_NO_WAIT);

	k_thread_name_set(ssm, "net_socket_service");

	return 0;
}
#endif

void socket_service_init(void)
{
	(void)init_socket_service();
}
