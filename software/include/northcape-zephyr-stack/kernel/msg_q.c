/*
 * Copyright (c) 2016 Wind River Systems, Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file
 * @brief Message queues.
 */


#include <zephyr/kernel.h>
#include <zephyr/kernel_structs.h>

#include <zephyr/toolchain.h>
#include <zephyr/linker/sections.h>
#include <string.h>
#include <ksched.h>
#include <wait_q.h>
#include <zephyr/sys/dlist.h>
#include <zephyr/sys/math_extras.h>
#include <zephyr/init.h>
#include <zephyr/internal/syscall_handler.h>
#include <kernel_internal.h>
#include <zephyr/sys/check.h>

#ifdef CONFIG_SKADI_OS
#include <zephyr/skadi/skadi_subsystem.h>
#ifdef CONFIG_SKADI_LOADER
#include <zephyr/skadi/skadi_interface_wrapper.h>
#endif /* CONFIG_SKADI_LOADER */
#endif

#ifdef CONFIG_OBJ_CORE_MSGQ
static struct k_obj_type obj_type_msgq;
#endif /* CONFIG_OBJ_CORE_MSGQ */

#ifdef CONFIG_POLL
static inline void handle_poll_events(struct k_msgq *msgq, uint32_t state)
{
	z_handle_obj_poll_events(&msgq->poll_events, state);
}
#endif /* CONFIG_POLL */

void k_msgq_init(struct k_msgq *msgq, char *buffer, size_t msg_size,
		 uint32_t max_msgs)
{
	msgq->msg_size = msg_size;
	msgq->max_msgs = max_msgs;
	msgq->buffer_start = buffer;
	msgq->buffer_end = buffer + (max_msgs * msg_size);
	msgq->read_ptr = buffer;
	msgq->write_ptr = buffer;
	msgq->used_msgs = 0;
	msgq->flags = 0;
	z_waitq_init(&msgq->wait_q);
	msgq->lock = (struct k_spinlock) {};
#ifdef CONFIG_POLL
	sys_dlist_init(&msgq->poll_events);
#endif	/* CONFIG_POLL */

#ifdef CONFIG_OBJ_CORE_MSGQ
	k_obj_core_init_and_link(K_OBJ_CORE(msgq), &obj_type_msgq);
#endif /* CONFIG_OBJ_CORE_MSGQ */

	SYS_PORT_TRACING_OBJ_INIT(k_msgq, msgq);

	k_object_init(msgq);
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_INTERFACE_WRAPPER_INIT_GLOBAL(SKADI_MSGQ);
	#define INIT_FN(MSG_Q) k_msgq_init(MSG_Q, buffer, msg_size, max_msgs)
	#define FREE_FN(MSG_Q) (void)(MSG_Q);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_msgq_init, struct k_msgq *msgq, char *buffer, size_t msg_size, uint32_t max_msgs)
		SKADI_INTERFACE_WRAPPER_REGISTER(SKADI_MSGQ, struct k_msgq, INIT_FN, FREE_FN, msgq);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_init)
#endif


int z_impl_k_msgq_alloc_init(struct k_msgq *msgq, size_t msg_size,
			    uint32_t max_msgs)
{
	void *buffer;
	int ret;
	size_t total_size;

	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_msgq, alloc_init, msgq);

	if (size_mul_overflow(msg_size, max_msgs, &total_size)) {
		ret = -EINVAL;
	} else {
		buffer = z_thread_malloc(total_size);
		if (buffer != NULL) {
			k_msgq_init(msgq, buffer, msg_size, max_msgs);
			msgq->flags = K_MSGQ_FLAG_ALLOC;
			ret = 0;
		} else {
			ret = -ENOMEM;
		}
	}

	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_msgq, alloc_init, msgq, ret);

	return ret;
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_msgq_alloc_init, struct k_msgq *msgq, size_t msg_size, uint32_t max_msgs)
		return z_impl_k_msgq_alloc_init(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_MSGQ, struct k_msgq, msgq), msg_size, max_msgs);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_alloc_init)
#endif

#ifdef CONFIG_USERSPACE
int z_vrfy_k_msgq_alloc_init(struct k_msgq *msgq, size_t msg_size,
			    uint32_t max_msgs)
{
	K_OOPS(K_SYSCALL_OBJ_NEVER_INIT(msgq, K_OBJ_MSGQ));

	return z_impl_k_msgq_alloc_init(msgq, msg_size, max_msgs);
}
#include <zephyr/syscalls/k_msgq_alloc_init_mrsh.c>
#endif /* CONFIG_USERSPACE */

int k_msgq_cleanup(struct k_msgq *msgq)
{
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_msgq, cleanup, msgq);

	CHECKIF(z_waitq_head(&msgq->wait_q) != NULL) {
		SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_msgq, cleanup, msgq, -EBUSY);

		return -EBUSY;
	}

	if ((msgq->flags & K_MSGQ_FLAG_ALLOC) != 0U) {
		k_free(msgq->buffer_start);
		msgq->flags &= ~K_MSGQ_FLAG_ALLOC;
	}

	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_msgq, cleanup, msgq, 0);

	return 0;
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_msgq_cleanup, struct k_msgq *msgq)
		int ret = k_msgq_cleanup(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_MSGQ, struct k_msgq, msgq));
		
		SKADI_INTERFACE_WRAPPER_REMOVE(SKADI_MSGQ, msgq);

		return ret;
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_cleanup)
#endif


int z_impl_k_msgq_put(struct k_msgq *msgq, const void *data, k_timeout_t timeout)
{
	__ASSERT(!arch_is_in_isr() || K_TIMEOUT_EQ(timeout, K_NO_WAIT), "");

	struct k_thread *pending_thread;
	k_spinlock_key_t key;
	int result;

	key = k_spin_lock(&msgq->lock);

	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_msgq, put, msgq, timeout);

	if (msgq->used_msgs < msgq->max_msgs) {
		/* message queue isn't full */
		pending_thread = z_unpend_first_thread(&msgq->wait_q);
		if (pending_thread != NULL) {
			SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_msgq, put, msgq, timeout, 0);

			/* give message to waiting thread */
			(void)memcpy(pending_thread->base.swap_data, data,
			       msgq->msg_size);
			/* wake up waiting thread */
			arch_thread_return_value_set(pending_thread, 0);
			z_ready_thread(pending_thread);
			z_reschedule(&msgq->lock, key);
			return 0;
		} else {
			/* put message in queue */
			__ASSERT_NO_MSG(msgq->write_ptr >= msgq->buffer_start &&
					msgq->write_ptr < msgq->buffer_end);
			(void)memcpy(msgq->write_ptr, (char *)data, msgq->msg_size);
			msgq->write_ptr += msgq->msg_size;
			if (msgq->write_ptr == msgq->buffer_end) {
				msgq->write_ptr = msgq->buffer_start;
			}
			msgq->used_msgs++;
#ifdef CONFIG_POLL
			handle_poll_events(msgq, K_POLL_STATE_MSGQ_DATA_AVAILABLE);
#endif /* CONFIG_POLL */
		}
		result = 0;
	} else if (K_TIMEOUT_EQ(timeout, K_NO_WAIT)) {
		/* don't wait for message space to become available */
		result = -ENOMSG;
	} else {
		SYS_PORT_TRACING_OBJ_FUNC_BLOCKING(k_msgq, put, msgq, timeout);

		/* wait for put message success, failure, or timeout */
		_current->base.swap_data = (void *) data;

		result = z_pend_curr(&msgq->lock, key, &msgq->wait_q, timeout);
		SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_msgq, put, msgq, timeout, result);
		return result;
	}

	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_msgq, put, msgq, timeout, result);

	k_spin_unlock(&msgq->lock, key);

	return result;
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_msgq_put, struct k_msgq *msgq, const void *data, k_timeout_t timeout)
		return z_impl_k_msgq_put(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_MSGQ, struct k_msgq, msgq), data, timeout);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_put)
#endif

#ifdef CONFIG_USERSPACE
static inline int z_vrfy_k_msgq_put(struct k_msgq *msgq, const void *data,
				    k_timeout_t timeout)
{
	K_OOPS(K_SYSCALL_OBJ(msgq, K_OBJ_MSGQ));
	K_OOPS(K_SYSCALL_MEMORY_READ(data, msgq->msg_size));

	return z_impl_k_msgq_put(msgq, data, timeout);
}
#include <zephyr/syscalls/k_msgq_put_mrsh.c>
#endif /* CONFIG_USERSPACE */

void z_impl_k_msgq_get_attrs(struct k_msgq *msgq, struct k_msgq_attrs *attrs)
{
	attrs->msg_size = msgq->msg_size;
	attrs->max_msgs = msgq->max_msgs;
	attrs->used_msgs = msgq->used_msgs;
}

#ifdef CONFIG_USERSPACE
static inline void z_vrfy_k_msgq_get_attrs(struct k_msgq *msgq,
					   struct k_msgq_attrs *attrs)
{
	K_OOPS(K_SYSCALL_OBJ(msgq, K_OBJ_MSGQ));
	K_OOPS(K_SYSCALL_MEMORY_WRITE(attrs, sizeof(struct k_msgq_attrs)));
	z_impl_k_msgq_get_attrs(msgq, attrs);
}
#include <zephyr/syscalls/k_msgq_get_attrs_mrsh.c>
#endif /* CONFIG_USERSPACE */

int z_impl_k_msgq_get(struct k_msgq *msgq, void *data, k_timeout_t timeout)
{
	__ASSERT(!arch_is_in_isr() || K_TIMEOUT_EQ(timeout, K_NO_WAIT), "");

	k_spinlock_key_t key;
	struct k_thread *pending_thread;
	int result;

	key = k_spin_lock(&msgq->lock);

	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_msgq, get, msgq, timeout);

	if (msgq->used_msgs > 0U) {
		/* take first available message from queue */
		(void)memcpy((char *)data, msgq->read_ptr, msgq->msg_size);
		msgq->read_ptr += msgq->msg_size;
		if (msgq->read_ptr == msgq->buffer_end) {
			msgq->read_ptr = msgq->buffer_start;
		}
		msgq->used_msgs--;

		/* handle first thread waiting to write (if any) */
		pending_thread = z_unpend_first_thread(&msgq->wait_q);
		if (pending_thread != NULL) {
			SYS_PORT_TRACING_OBJ_FUNC_BLOCKING(k_msgq, get, msgq, timeout);

			/* add thread's message to queue */
			__ASSERT_NO_MSG(msgq->write_ptr >= msgq->buffer_start &&
					msgq->write_ptr < msgq->buffer_end);
			(void)memcpy(msgq->write_ptr, (char *)pending_thread->base.swap_data,
			       msgq->msg_size);
			msgq->write_ptr += msgq->msg_size;
			if (msgq->write_ptr == msgq->buffer_end) {
				msgq->write_ptr = msgq->buffer_start;
			}
			msgq->used_msgs++;

			/* wake up waiting thread */
			arch_thread_return_value_set(pending_thread, 0);
			z_ready_thread(pending_thread);
			z_reschedule(&msgq->lock, key);

			SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_msgq, get, msgq, timeout, 0);

			return 0;
		}
		result = 0;
	} else if (K_TIMEOUT_EQ(timeout, K_NO_WAIT)) {
		/* don't wait for a message to become available */
		result = -ENOMSG;
	} else {
		SYS_PORT_TRACING_OBJ_FUNC_BLOCKING(k_msgq, get, msgq, timeout);

		/* wait for get message success or timeout */
		_current->base.swap_data = data;

		result = z_pend_curr(&msgq->lock, key, &msgq->wait_q, timeout);
		SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_msgq, get, msgq, timeout, result);
		return result;
	}

	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_msgq, get, msgq, timeout, result);

	k_spin_unlock(&msgq->lock, key);

	return result;
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_msgq_get, struct k_msgq *msgq, void *data, k_timeout_t timeout)
		return z_impl_k_msgq_get(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_MSGQ, struct k_msgq, msgq), data, timeout);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_get)
#endif

#ifdef CONFIG_USERSPACE
static inline int z_vrfy_k_msgq_get(struct k_msgq *msgq, void *data,
				    k_timeout_t timeout)
{
	K_OOPS(K_SYSCALL_OBJ(msgq, K_OBJ_MSGQ));
	K_OOPS(K_SYSCALL_MEMORY_WRITE(data, msgq->msg_size));

	return z_impl_k_msgq_get(msgq, data, timeout);
}
#include <zephyr/syscalls/k_msgq_get_mrsh.c>
#endif /* CONFIG_USERSPACE */

int z_impl_k_msgq_peek(struct k_msgq *msgq, void *data)
{
	k_spinlock_key_t key;
	int result;

	key = k_spin_lock(&msgq->lock);

	if (msgq->used_msgs > 0U) {
		/* take first available message from queue */
		(void)memcpy((char *)data, msgq->read_ptr, msgq->msg_size);
		result = 0;
	} else {
		/* don't wait for a message to become available */
		result = -ENOMSG;
	}

	SYS_PORT_TRACING_OBJ_FUNC(k_msgq, peek, msgq, result);

	k_spin_unlock(&msgq->lock, key);

	return result;
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_msgq_peek, struct k_msgq *msgq, void *data)
		return z_impl_k_msgq_peek(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_MSGQ, struct k_msgq, msgq), data);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_peek)
#endif

#ifdef CONFIG_USERSPACE
static inline int z_vrfy_k_msgq_peek(struct k_msgq *msgq, void *data)
{
	K_OOPS(K_SYSCALL_OBJ(msgq, K_OBJ_MSGQ));
	K_OOPS(K_SYSCALL_MEMORY_WRITE(data, msgq->msg_size));

	return z_impl_k_msgq_peek(msgq, data);
}
#include <zephyr/syscalls/k_msgq_peek_mrsh.c>
#endif /* CONFIG_USERSPACE */

int z_impl_k_msgq_peek_at(struct k_msgq *msgq, void *data, uint32_t idx)
{
	k_spinlock_key_t key;
	int result;
	uint32_t bytes_to_end;
	uint32_t byte_offset;
	char *start_addr;

	key = k_spin_lock(&msgq->lock);

	if (msgq->used_msgs > idx) {
		bytes_to_end = (msgq->buffer_end - msgq->read_ptr);
		byte_offset = idx * msgq->msg_size;
		start_addr = msgq->read_ptr;
		/* check item available in start/end of ring buffer */
		if (bytes_to_end <= byte_offset) {
			/* Tweak the values in case */
			byte_offset -= bytes_to_end;
			/* wrap-around is required */
			start_addr = msgq->buffer_start;
		}
		(void)memcpy(data, start_addr + byte_offset, msgq->msg_size);
		result = 0;
	} else {
		/* don't wait for a message to become available */
		result = -ENOMSG;
	}

	SYS_PORT_TRACING_OBJ_FUNC(k_msgq, peek, msgq, result);

	k_spin_unlock(&msgq->lock, key);

	return result;
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __skadi_msgq_peek_at, struct k_msgq *msgq, void *data, uint32_t idx)
		return z_impl_k_msgq_peek_at(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_MSGQ, struct k_msgq, msgq), data, idx);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_peek_at)
#endif

#ifdef CONFIG_USERSPACE
static inline int z_vrfy_k_msgq_peek_at(struct k_msgq *msgq, void *data, uint32_t idx)
{
	K_OOPS(K_SYSCALL_OBJ(msgq, K_OBJ_MSGQ));
	K_OOPS(K_SYSCALL_MEMORY_WRITE(data, msgq->msg_size));

	return z_impl_k_msgq_peek_at(msgq, data, idx);
}
#include <zephyr/syscalls/k_msgq_peek_at_mrsh.c>
#endif /* CONFIG_USERSPACE */

void z_impl_k_msgq_purge(struct k_msgq *msgq)
{
	k_spinlock_key_t key;
	struct k_thread *pending_thread;

	key = k_spin_lock(&msgq->lock);

	SYS_PORT_TRACING_OBJ_FUNC(k_msgq, purge, msgq);

	/* wake up any threads that are waiting to write */
	for (pending_thread = z_unpend_first_thread(&msgq->wait_q); pending_thread != NULL;
		 pending_thread = z_unpend_first_thread(&msgq->wait_q)) {
		arch_thread_return_value_set(pending_thread, -ENOMSG);
		z_ready_thread(pending_thread);
	}

	msgq->used_msgs = 0;
	msgq->read_ptr = msgq->write_ptr;

	z_reschedule(&msgq->lock, key);
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_msgq_purge, struct k_msgq *msgq)
		z_impl_k_msgq_purge(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_MSGQ, struct k_msgq, msgq));
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_purge)
#endif


#ifdef CONFIG_SKADI_LOADER

	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_msgq_get_attrs, struct k_msgq *msgq, struct k_msgq_attrs *attrs)
		msgq = SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_MSGQ, struct k_msgq, msgq);

		attrs->msg_size = msgq->msg_size;
		attrs->max_msgs = msgq->max_msgs;
		attrs->used_msgs = msgq->used_msgs;
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_get_attrs)
	
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(uint32_t, __skadi_msgq_num_used_get, struct k_msgq *msgq)
		return SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_MSGQ, struct k_msgq, msgq)->used_msgs;
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_msgq_num_used_get)
#endif

#ifdef CONFIG_USERSPACE
static inline void z_vrfy_k_msgq_purge(struct k_msgq *msgq)
{
	K_OOPS(K_SYSCALL_OBJ(msgq, K_OBJ_MSGQ));
	z_impl_k_msgq_purge(msgq);
}
#include <zephyr/syscalls/k_msgq_purge_mrsh.c>

static inline uint32_t z_vrfy_k_msgq_num_free_get(struct k_msgq *msgq)
{
	K_OOPS(K_SYSCALL_OBJ(msgq, K_OBJ_MSGQ));
	return z_impl_k_msgq_num_free_get(msgq);
}
#include <zephyr/syscalls/k_msgq_num_free_get_mrsh.c>

static inline uint32_t z_vrfy_k_msgq_num_used_get(struct k_msgq *msgq)
{
	K_OOPS(K_SYSCALL_OBJ(msgq, K_OBJ_MSGQ));
	return z_impl_k_msgq_num_used_get(msgq);
}
#include <zephyr/syscalls/k_msgq_num_used_get_mrsh.c>

#endif /* CONFIG_USERSPACE */

#ifdef CONFIG_OBJ_CORE_MSGQ
static int init_msgq_obj_core_list(void)
{
	/* Initialize msgq object type */

	z_obj_type_init(&obj_type_msgq, K_OBJ_TYPE_MSGQ_ID,
			offsetof(struct k_msgq, obj_core));

	/* Initialize and link statically defined message queues */

	STRUCT_SECTION_FOREACH(k_msgq, msgq) {
		k_obj_core_init_and_link(K_OBJ_CORE(msgq), &obj_type_msgq);
	}

	return 0;
};

SYS_INIT(init_msgq_obj_core_list, PRE_KERNEL_1,
	 CONFIG_KERNEL_INIT_PRIORITY_OBJECTS);

#endif /* CONFIG_OBJ_CORE_MSGQ */

#if defined(CONFIG_SKADI_LOADER) && !defined(SKADI_SUBSYSTEM)

/* not compiled into subsystem - need to manually init the trampolines */
__boot_func static int msgq_init_trampolines(void){
    bool init_ok = true;

	init_ok &= __skadi_msgq_init_register_init_function();
	init_ok &= __skadi_msgq_alloc_init_register_init_function();
	init_ok &= __skadi_msgq_cleanup_register_init_function();
	init_ok &= __skadi_msgq_put_register_init_function();
	init_ok &= __skadi_msgq_get_register_init_function();
	init_ok &= __skadi_msgq_peek_register_init_function();
	init_ok &= __skadi_msgq_peek_at_register_init_function();
	init_ok &= __skadi_msgq_purge_register_init_function();
	
    return init_ok == true ? 0 : -ENOMEM;
}

// TODO fine-tune priority?
SYS_INIT(msgq_init_trampolines, PRE_KERNEL_1, CONFIG_LOADER_SKADI_TRAMPOLINE_INIT_PRIO);

#endif /* SKADI_SUBSYSTEM */
