/*
 * Copyright (c) 2016 Intel Corporation.
 *
 * SPDX-License-Identifier: Apache-2.0
 */


#ifdef CONFIG_SKADI_OS
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/skadi_work.h>
#include <zephyr/skadi/skadi_msg_queue.h>
#include <zephyr/skadi/skadi_mutex.h>
#include <zephyr/skadi/skadi_sem.h>
#endif

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(net_mgmt, CONFIG_NET_MGMT_EVENT_LOG_LEVEL);

#include <zephyr/kernel.h>
#include <zephyr/toolchain.h>
#include <zephyr/linker/sections.h>

#include <zephyr/sys/util.h>
#include <zephyr/sys/slist.h>
#include <zephyr/net/net_mgmt.h>
#include <zephyr/debug/stack.h>

#include "net_private.h"

struct mgmt_event_entry {
#if defined(CONFIG_NET_MGMT_EVENT_INFO)
#if defined(CONFIG_NET_MGMT_EVENT_QUEUE)
	uint8_t info[NET_EVENT_INFO_MAX_SIZE];
#else
	const void *info;
#endif /* CONFIG_NET_MGMT_EVENT_QUEUE */
	size_t info_length;
#endif /* CONFIG_NET_MGMT_EVENT_INFO */
	uint32_t event;
	struct net_if *iface;
};

BUILD_ASSERT((sizeof(struct mgmt_event_entry) % sizeof(uint32_t)) == 0,
	     "The structure must be a multiple of sizeof(uint32_t)");

struct mgmt_event_wait {
#ifdef CONFIG_SKADI_OS
	struct k_sem *sync_call;
#else
	struct k_sem sync_call;
#endif
	struct net_if *iface;
};

#ifdef CONFIG_SKADI_OS
	static struct k_mutex *net_mgmt_callback_lock;
#else
	static K_MUTEX_DEFINE(net_mgmt_callback_lock);
#endif

#if defined(CONFIG_NET_MGMT_EVENT_THREAD)
#ifdef CONFIG_SKADI_OS
static k_thread_stack_t *mgmt_stack;

#else
static K_KERNEL_STACK_DEFINE(mgmt_stack, CONFIG_NET_MGMT_EVENT_STACK_SIZE);
#endif

static struct k_work_q mgmt_work_q_obj;
#endif

static uint32_t global_event_mask;
static sys_slist_t event_callbacks = SYS_SLIST_STATIC_INIT(&event_callbacks);

/* Forward declaration for the actual caller */
static void mgmt_run_callbacks(const struct mgmt_event_entry * const mgmt_event);

#if defined(CONFIG_NET_MGMT_EVENT_QUEUE)

#ifdef CONFIG_SKADI_OS
	static struct k_mutex *net_mgmt_event_lock;
#else
	static K_MUTEX_DEFINE(net_mgmt_event_lock);
#endif
#ifdef CONFIG_SKADI_OS
static struct mgmt_event_entry *new_event, *retrieved_event;
#else
/* event structure used to prevent increasing the stack usage on the caller thread */
static struct mgmt_event_entry new_event;
#endif
#ifdef CONFIG_SKADI_OS
struct k_msgq *event_msgq;
#else
K_MSGQ_DEFINE(event_msgq, sizeof(struct mgmt_event_entry),
	      CONFIG_NET_MGMT_EVENT_QUEUE_SIZE, sizeof(uint32_t));
#endif

static struct k_work_q *mgmt_work_q = COND_CODE_1(CONFIG_NET_MGMT_EVENT_SYSTEM_WORKQUEUE,
	(&k_sys_work_q), (&mgmt_work_q_obj));

#ifdef CONFIG_SKADI_OS
static struct k_work *mgmt_work;
#else
static void mgmt_event_work_handler(struct k_work *work);
static K_WORK_DEFINE(mgmt_work, mgmt_event_work_handler);
#endif

static inline void mgmt_push_event(uint32_t mgmt_event, struct net_if *iface,
				   const void *info, size_t length)
{
#ifndef CONFIG_NET_MGMT_EVENT_INFO
	ARG_UNUSED(info);
	ARG_UNUSED(length);
#endif /* CONFIG_NET_MGMT_EVENT_INFO */

#ifdef CONFIG_SKADI_OS
    skadi_mutex_lock(net_mgmt_event_lock, K_FOREVER);
#else
    k_mutex_lock(&net_mgmt_event_lock, K_FOREVER);
#endif

#ifdef CONFIG_SKADI_OS
	memset(new_event, 0, sizeof(struct mgmt_event_entry));
#else
	memset(&new_event, 0, sizeof(struct mgmt_event_entry));
#endif

#ifdef CONFIG_NET_MGMT_EVENT_INFO
	if (info && length) {
		if (length <= NET_EVENT_INFO_MAX_SIZE) {
#ifdef CONFIG_SKADI_OS
			memcpy(new_event->info, info, length);
			new_event->info_length = length;
#else
			memcpy(new_event.info, info, length);
			new_event.info_length = length;
#endif
		} else {
			NET_ERR("Event %u info length %zu > max size %zu",
				mgmt_event, length, NET_EVENT_INFO_MAX_SIZE);
#ifdef CONFIG_SKADI_OS
    			skadi_mutex_unlock(net_mgmt_event_lock);
#else
    			k_mutex_unlock(&net_mgmt_event_lock);
#endif

			return;
		}
	}
#endif /* CONFIG_NET_MGMT_EVENT_INFO */

#ifdef CONFIG_SKADI_OS
	new_event->event = mgmt_event;
	new_event->iface = iface;

	if (skadi_msgq_put(event_msgq, new_event,
		K_MSEC(CONFIG_NET_MGMT_EVENT_QUEUE_TIMEOUT)) != 0) {
		NET_WARN("Failure to push event (%u), "
			 "try increasing the 'CONFIG_NET_MGMT_EVENT_QUEUE_SIZE' "
			 "or 'CONFIG_NET_MGMT_EVENT_QUEUE_TIMEOUT' options.",
			 mgmt_event);
	}
#else
	new_event.event = mgmt_event;
	new_event.iface = iface;

	if (k_msgq_put(&event_msgq, &new_event,
		K_MSEC(CONFIG_NET_MGMT_EVENT_QUEUE_TIMEOUT)) != 0) {
		NET_WARN("Failure to push event (%u), "
			 "try increasing the 'CONFIG_NET_MGMT_EVENT_QUEUE_SIZE' "
			 "or 'CONFIG_NET_MGMT_EVENT_QUEUE_TIMEOUT' options.",
			 mgmt_event);
	}
#endif
#ifdef CONFIG_SKADI_OS
    skadi_mutex_unlock(net_mgmt_event_lock);
#else
    k_mutex_unlock(&net_mgmt_event_lock);
#endif

#ifdef CONFIG_SKADI_OS
	__ASSERT_NO_MSG(mgmt_work);
	skadi_work_submit_to_queue(mgmt_work_q, mgmt_work);
#else
	k_work_submit_to_queue(mgmt_work_q, &mgmt_work);
#endif
}


#ifdef CONFIG_SKADI_OS
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, mgmt_event_work_handler, struct k_work *work)
{
	if(!retrieved_event){
		LOG_ERR("Could not allocated management event!");
		return;
	}

	ARG_UNUSED(work);

	while (skadi_msgq_get(event_msgq, retrieved_event, K_NO_WAIT) == 0) {
		NET_DBG("Handling events, forwarding it relevantly");

		mgmt_run_callbacks(retrieved_event);

		/* forcefully give up our timeslot, to give time to the callback */
		skadi_subsystem_yield();
	}
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(mgmt_event_work_handler)
#else
static void mgmt_event_work_handler(struct k_work *work)
{
	struct mgmt_event_entry mgmt_event;

	ARG_UNUSED(work);

	while (k_msgq_get(&event_msgq, &mgmt_event, K_NO_WAIT) == 0) {
		NET_DBG("Handling events, forwarding it relevantly");

		mgmt_run_callbacks(&mgmt_event);

		/* forcefully give up our timeslot, to give time to the callback */
		k_yield();
	}
}
#endif /* CONFIG_SKADI_OS */

#else

static inline void mgmt_push_event(uint32_t event, struct net_if *iface,
				   const void *info, size_t length)
{
#ifndef CONFIG_NET_MGMT_EVENT_INFO
	ARG_UNUSED(info);
	ARG_UNUSED(length);
#endif /* CONFIG_NET_MGMT_EVENT_INFO */
	const struct mgmt_event_entry mgmt_event = {
#if defined(CONFIG_NET_MGMT_EVENT_INFO)
		.info = info,
		.info_length = length,
#endif /* CONFIG_NET_MGMT_EVENT_INFO */
		.event = event,
		.iface = iface,
	};

	mgmt_run_callbacks(&mgmt_event);
}

#endif /* CONFIG_NET_MGMT_EVENT_QUEUE */

static inline void mgmt_add_event_mask(uint32_t event_mask)
{
	global_event_mask |= event_mask;
}

static inline void mgmt_rebuild_global_event_mask(void)
{
	struct net_mgmt_event_callback *cb, *tmp;

	global_event_mask = 0U;

	STRUCT_SECTION_FOREACH(net_mgmt_event_static_handler, it) {
		mgmt_add_event_mask(it->event_mask);
	}

	SYS_SLIST_FOR_EACH_CONTAINER_SAFE(&event_callbacks, cb, tmp, node) {
		mgmt_add_event_mask(cb->event_mask);
	}
}

static inline bool mgmt_is_event_handled(uint32_t mgmt_event)
{
	return (((NET_MGMT_GET_LAYER(mgmt_event) &
		  NET_MGMT_GET_LAYER(global_event_mask)) ==
		 NET_MGMT_GET_LAYER(mgmt_event)) &&
		((NET_MGMT_GET_LAYER_CODE(mgmt_event) &
		  NET_MGMT_GET_LAYER_CODE(global_event_mask)) ==
		 NET_MGMT_GET_LAYER_CODE(mgmt_event)) &&
		((NET_MGMT_GET_COMMAND(mgmt_event) &
		  NET_MGMT_GET_COMMAND(global_event_mask)) ==
		 NET_MGMT_GET_COMMAND(mgmt_event)));
}

static inline void mgmt_run_slist_callbacks(const struct mgmt_event_entry * const mgmt_event)
{
	sys_snode_t *prev = NULL;
	struct net_mgmt_event_callback *cb, *tmp;

	/* Readable layer code is starting from 1, thus the increment */
	NET_DBG("Event layer %u code %u cmd %u",
		NET_MGMT_GET_LAYER(mgmt_event->event) + 1,
		NET_MGMT_GET_LAYER_CODE(mgmt_event->event),
		NET_MGMT_GET_COMMAND(mgmt_event->event));

	SYS_SLIST_FOR_EACH_CONTAINER_SAFE(&event_callbacks, cb, tmp, node) {
		if (!(NET_MGMT_GET_LAYER(mgmt_event->event) ==
		      NET_MGMT_GET_LAYER(cb->event_mask)) ||
		    !(NET_MGMT_GET_LAYER_CODE(mgmt_event->event) ==
		      NET_MGMT_GET_LAYER_CODE(cb->event_mask)) ||
		    (NET_MGMT_GET_COMMAND(mgmt_event->event) &&
		     NET_MGMT_GET_COMMAND(cb->event_mask) &&
		     !(NET_MGMT_GET_COMMAND(mgmt_event->event) &
		       NET_MGMT_GET_COMMAND(cb->event_mask)))) {
			continue;
		}

#ifdef CONFIG_NET_MGMT_EVENT_INFO
		if (mgmt_event->info_length) {
			cb->info = (void *)mgmt_event->info;
			cb->info_length = mgmt_event->info_length;
		} else {
			cb->info = NULL;
			cb->info_length = 0;
		}
#endif /* CONFIG_NET_MGMT_EVENT_INFO */

		if (NET_MGMT_EVENT_SYNCHRONOUS(cb->event_mask)) {
#ifdef CONFIG_SKADI_OS

			if (cb->user_data &&
			    cb->user_data != mgmt_event->iface) {
				continue;
			}

			NET_DBG("Unlocking %p synchronous call", cb);

			cb->raised_event = mgmt_event->event;
			cb->user_data = mgmt_event->iface;
#else

			struct mgmt_event_wait *sync_data =
				CONTAINER_OF(cb->sync_call,
					     struct mgmt_event_wait, sync_call);

			if (sync_data->iface &&
			    sync_data->iface != mgmt_event->iface) {
				continue;
			}

			NET_DBG("Unlocking %p synchronous call", cb);

			cb->raised_event = mgmt_event->event;
			sync_data->iface = mgmt_event->iface;
#endif

			sys_slist_remove(&event_callbacks, prev, &cb->node);

#ifdef CONFIG_SKADI_OS
			skadi_sem_give(cb->sync_call);
#else
			k_sem_give(cb->sync_call);
#endif
		} else {
			NET_DBG("Running callback %p : %p",
				cb, cb->handler);

			cb->handler(cb, mgmt_event->event, mgmt_event->iface);
			prev = &cb->node;
		}
	}

#ifdef CONFIG_NET_DEBUG_MGMT_EVENT_STACK
	log_stack_usage(&mgmt_work_q->thread);
#endif
}

static inline void mgmt_run_static_callbacks(const struct mgmt_event_entry * const mgmt_event)
{
	STRUCT_SECTION_FOREACH(net_mgmt_event_static_handler, it) {
		if (!(NET_MGMT_GET_LAYER(mgmt_event->event) ==
		      NET_MGMT_GET_LAYER(it->event_mask)) ||
		    !(NET_MGMT_GET_LAYER_CODE(mgmt_event->event) ==
		      NET_MGMT_GET_LAYER_CODE(it->event_mask)) ||
		    (NET_MGMT_GET_COMMAND(mgmt_event->event) &&
		     NET_MGMT_GET_COMMAND(it->event_mask) &&
		     !(NET_MGMT_GET_COMMAND(mgmt_event->event) &
		       NET_MGMT_GET_COMMAND(it->event_mask)))) {
			continue;
		}

		it->handler(mgmt_event->event, mgmt_event->iface,
#ifdef CONFIG_NET_MGMT_EVENT_INFO
			    (void *)mgmt_event->info, mgmt_event->info_length,
#else
			    NULL, 0U,
#endif
			    it->user_data);
	}
}

static void mgmt_run_callbacks(const struct mgmt_event_entry * const mgmt_event)
{
	/* take the lock to prevent changes to the callback structure during use */
	(void)
#ifdef CONFIG_SKADI_OS
    skadi_mutex_lock(net_mgmt_callback_lock, K_FOREVER);
#else
    k_mutex_lock(&net_mgmt_callback_lock, K_FOREVER);
#endif

	mgmt_run_static_callbacks(mgmt_event);
	mgmt_run_slist_callbacks(mgmt_event);

	(void)
#ifdef CONFIG_SKADI_OS
    skadi_mutex_unlock(net_mgmt_callback_lock);
#else
    k_mutex_unlock(&net_mgmt_callback_lock);
#endif
}

static int mgmt_event_wait_call(struct net_if *iface,
				uint32_t mgmt_event_mask,
				uint32_t *raised_event,
				struct net_if **event_iface,
				const void **info,
				size_t *info_length,
				k_timeout_t timeout)
{
#ifdef CONFIG_SKADI_OS
	struct mgmt_event_wait sync_data = {
		.sync_call = NULL,
	};
	struct net_mgmt_event_callback sync = {
		.sync_call = NULL,
		.event_mask = mgmt_event_mask | NET_MGMT_SYNC_EVENT_BIT,
		.user_data = iface
	};
#else
	struct mgmt_event_wait sync_data = {
		.sync_call = Z_SEM_INITIALIZER(sync_data.sync_call, 0, 1),
	};
	struct net_mgmt_event_callback sync = {
		.sync_call = &sync_data.sync_call,
		.event_mask = mgmt_event_mask | NET_MGMT_SYNC_EVENT_BIT,
	};
#endif
	int ret;

	if (iface) {
		sync_data.iface = iface;
	}

	NET_DBG("Synchronous event 0x%08x wait %p", sync.event_mask, &sync);

	net_mgmt_add_event_callback(&sync);

#ifdef CONFIG_SKADI_OS
	sync.sync_call = skadi_allocator_alloc_rw(sizeof(*sync.sync_call));
	if(!sync.sync_call){
		LOG_ERR("Could not alloc sync call!");
		return -ENOMEM;
	}
	skadi_sem_init(sync.sync_call, 0, 1);
	sync_data.sync_call = sync.sync_call;

	ret = skadi_sem_take(sync.sync_call, timeout);
#else
	ret = k_sem_take(sync.sync_call, timeout);
#endif
	if (ret < 0) {
		if (ret == -EAGAIN) {
			ret = -ETIMEDOUT;
		}

		net_mgmt_del_event_callback(&sync);
		return ret;
	}

	if (raised_event) {
		*raised_event = sync.raised_event;
	}

	if (event_iface) {
		*event_iface = sync_data.iface;
	}

#ifdef CONFIG_NET_MGMT_EVENT_INFO
	if (info) {
		*info = sync.info;

		if (info_length) {
			*info_length = sync.info_length;
		}
	}
#endif /* CONFIG_NET_MGMT_EVENT_INFO */

	return ret;
}

void net_mgmt_add_event_callback(struct net_mgmt_event_callback *cb)
{
	NET_DBG("Adding event callback %p", cb);

#ifdef CONFIG_SKADI_OS
    skadi_mutex_lock(net_mgmt_callback_lock, K_FOREVER);
#else
    k_mutex_lock(&net_mgmt_callback_lock, K_FOREVER);
#endif

	/* Remove the callback if it already exists to avoid loop */
	sys_slist_find_and_remove(&event_callbacks, &cb->node);

	sys_slist_prepend(&event_callbacks, &cb->node);

	mgmt_add_event_mask(cb->event_mask);

#ifdef CONFIG_SKADI_OS
    skadi_mutex_unlock(net_mgmt_callback_lock);
#else
    k_mutex_unlock(&net_mgmt_callback_lock);
#endif
}

void net_mgmt_del_event_callback(struct net_mgmt_event_callback *cb)
{
	NET_DBG("Deleting event callback %p", cb);

#ifdef CONFIG_SKADI_OS
    skadi_mutex_lock(net_mgmt_callback_lock, K_FOREVER);
#else
    k_mutex_lock(&net_mgmt_callback_lock, K_FOREVER);
#endif

	sys_slist_find_and_remove(&event_callbacks, &cb->node);

	mgmt_rebuild_global_event_mask();

#ifdef CONFIG_SKADI_OS
    skadi_mutex_unlock(net_mgmt_callback_lock);
#else
    k_mutex_unlock(&net_mgmt_callback_lock);
#endif
}

void net_mgmt_event_notify_with_info(uint32_t mgmt_event, struct net_if *iface,
				     const void *info, size_t length)
{
	if (mgmt_is_event_handled(mgmt_event)) {
		/* Readable layer code is starting from 1, thus the increment */
		NET_DBG("Notifying Event layer %u code %u type %u",
			NET_MGMT_GET_LAYER(mgmt_event) + 1,
			NET_MGMT_GET_LAYER_CODE(mgmt_event),
			NET_MGMT_GET_COMMAND(mgmt_event));

		mgmt_push_event(mgmt_event, iface, info, length);
	}
}

int net_mgmt_event_wait(uint32_t mgmt_event_mask,
			uint32_t *raised_event,
			struct net_if **iface,
			const void **info,
			size_t *info_length,
			k_timeout_t timeout)
{
	return mgmt_event_wait_call(NULL, mgmt_event_mask,
				    raised_event, iface, info, info_length,
				    timeout);
}

int net_mgmt_event_wait_on_iface(struct net_if *iface,
				 uint32_t mgmt_event_mask,
				 uint32_t *raised_event,
				 const void **info,
				 size_t *info_length,
				 k_timeout_t timeout)
{
	NET_ASSERT(NET_MGMT_ON_IFACE(mgmt_event_mask));
	NET_ASSERT(iface);

	return mgmt_event_wait_call(iface, mgmt_event_mask,
				    raised_event, NULL, info, info_length,
				    timeout);
}

void net_mgmt_event_init(void)
{
	mgmt_rebuild_global_event_mask();
	size_t stack_size;
	struct k_work_queue_config *q_cfg_p;

#if defined(CONFIG_NET_MGMT_EVENT_THREAD)
#if defined(CONFIG_NET_TC_THREAD_COOPERATIVE)
/* Lowest priority cooperative thread */
#define THREAD_PRIORITY K_PRIO_COOP(CONFIG_NUM_COOP_PRIORITIES - 1)
#else
#define THREAD_PRIORITY K_PRIO_PREEMPT(CONFIG_NUM_PREEMPT_PRIORITIES - 1)
#endif
	struct k_work_queue_config q_cfg = {
		.name = "net_mgmt",
		.no_yield = false,
	};

#ifdef CONFIG_SKADI_OS
	void* q_cfg_ptr;
	void *msgq_buffer;
    skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

	if(skadi_cap_ops_derive(&q_cfg, restriction, sizeof(q_cfg), skadi_get_capability_offset(&q_cfg), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &q_cfg_ptr) == false || q_cfg_ptr == 0){
		LOG_ERR("Could not derive queue config pointer!");
		return;
	}

	q_cfg_p = q_cfg_ptr;

	if(skadi_cap_ops_derive(mgmt_work_q, restriction, sizeof(*mgmt_work_q), skadi_get_capability_offset(mgmt_work_q), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &q_cfg_ptr) == false || q_cfg_ptr == 0){
		LOG_ERR("Could not derive queue config pointer!");
		return;
	}

	mgmt_work_q = q_cfg_ptr;

	mgmt_stack = skadi_allocator_alloc_rw(CONFIG_NET_TCP_WORKQ_STACK_SIZE);
	
	if(!mgmt_stack){
		LOG_ERR("Expected to be able to allocate management stack!");
		return;
	}

	stack_size = CONFIG_NET_TCP_WORKQ_STACK_SIZE;

	mgmt_work = skadi_allocator_alloc_rw(sizeof(*mgmt_work));

	if(!mgmt_work){
		LOG_ERR("Expected to be able to allocate management work!");
		return;
	}


	mgmt_work->handler = SKADI_SUBSYSTEM_FUNCTION_POINTER(mgmt_event_work_handler);

	event_msgq = skadi_allocator_alloc_rw(sizeof(*event_msgq));

	if(!event_msgq){
		LOG_ERR("Expected to be able to allocate message queue!");
		return;
	}

	msgq_buffer = skadi_allocator_alloc_rw(sizeof(struct mgmt_event_entry) * CONFIG_NET_MGMT_EVENT_QUEUE_SIZE);

	if(!msgq_buffer){
		LOG_ERR("Expected to be able to allocate message queue buffer!");
		return;
	}

	new_event = skadi_allocator_alloc_rw(sizeof(*new_event));
	retrieved_event = skadi_allocator_alloc_rw(sizeof(*retrieved_event));

	if(!new_event || !retrieved_event){
		LOG_ERR("Could not allocate events!");
		return;
	}

	net_mgmt_callback_lock = skadi_allocator_alloc_rw(sizeof(*net_mgmt_callback_lock));

	if(!net_mgmt_callback_lock){
		LOG_ERR("Could not allocate callback lock!");
		return;
	}

	skadi_mutex_init(net_mgmt_callback_lock);

	net_mgmt_event_lock = skadi_allocator_alloc_rw(sizeof(*net_mgmt_event_lock));

	if(!net_mgmt_event_lock){
		LOG_ERR("Could not allocate callback lock!");
		return;
	}

	skadi_mutex_init(net_mgmt_event_lock);

	skadi_msgq_init(event_msgq, msgq_buffer, sizeof(struct mgmt_event_entry), CONFIG_NET_MGMT_EVENT_QUEUE_SIZE);
#else
	stack_size = K_KERNEL_STACK_SIZEOF(mgmt_stack);
	q_cfg_p = &q_cfg;
#endif

#ifdef CONFIG_SKADI_OS
	skadi_work_init(mgmt_work, SKADI_SUBSYSTEM_FUNCTION_POINTER(mgmt_event_work_handler));

	skadi_work_queue_init(mgmt_work_q);
	skadi_work_queue_start(mgmt_work_q, mgmt_stack,
			   stack_size, THREAD_PRIORITY, q_cfg_p);

	(void)skadi_cap_ops_drop(q_cfg_p);
#else
	k_work_queue_init(mgmt_work_q);
	k_work_queue_start(mgmt_work_q, mgmt_stack,
			   stack_size, THREAD_PRIORITY, q_cfg_p);
#endif

	NET_DBG("Net MGMT initialized: queue of %u entries, stack size of %u",
		CONFIG_NET_MGMT_EVENT_QUEUE_SIZE,
		CONFIG_NET_MGMT_EVENT_STACK_SIZE);
#endif /* CONFIG_NET_MGMT_EVENT_THREAD */
}
