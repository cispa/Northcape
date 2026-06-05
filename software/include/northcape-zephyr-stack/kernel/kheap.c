/*
 * Copyright (c) 2020 Intel Corporation
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/init.h>
#include <zephyr/linker/linker-defs.h>
#include <zephyr/sys/iterable_sections.h>
/* private kernel APIs */
#include <ksched.h>
#include <wait_q.h>

#ifdef CONFIG_SKADI_OS
#include <zephyr/skadi/skadi_subsystem.h>
#ifdef CONFIG_SKADI_LOADER
#include <zephyr/skadi/skadi_interface_wrapper.h>
#endif /* CONFIG_SKADI_LOADER */
#endif

void k_heap_init(struct k_heap *heap, void *mem, size_t bytes)
{
	z_waitq_init(&heap->wait_q);
	sys_heap_init(&heap->heap, mem, bytes);

	SYS_PORT_TRACING_OBJ_INIT(k_heap, heap);
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_INTERFACE_WRAPPER_INIT_GLOBAL(SKADI_HEAP);
	#define INIT_FN(HEAP) k_heap_init(HEAP, mem, bytes)
	#define FREE_FN(HEAP) (void)(HEAP);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_heap_init, struct k_heap *heap, void *mem, size_t bytes)
		
		SKADI_INTERFACE_WRAPPER_REGISTER(SKADI_HEAP, struct k_heap, INIT_FN, FREE_FN, heap);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_heap_init)
#endif

static int statics_init(void)
{
	STRUCT_SECTION_FOREACH(k_heap, heap) {
#if defined(CONFIG_DEMAND_PAGING) && !defined(CONFIG_LINKER_GENERIC_SECTIONS_PRESENT_AT_BOOT)
		/* Some heaps may not present at boot, so we need to wait for
		 * paging mechanism to be initialized before we can initialize
		 * each heap.
		 */
		extern bool z_sys_post_kernel;
		bool do_clear = z_sys_post_kernel;

		/* During pre-kernel init, z_sys_post_kernel == false,
		 * initialize if within pinned region. Otherwise skip.
		 * In post-kernel init, z_sys_post_kernel == true, skip those in
		 * pinned region as they have already been initialized and
		 * possibly already in use. Otherwise initialize.
		 */
		if (lnkr_is_pinned((uint8_t *)heap) &&
		    lnkr_is_pinned((uint8_t *)&heap->wait_q) &&
		    lnkr_is_region_pinned((uint8_t *)heap->heap.init_mem,
					  heap->heap.init_bytes)) {
			do_clear = !do_clear;
		}

		if (do_clear)
#endif /* CONFIG_DEMAND_PAGING && !CONFIG_LINKER_GENERIC_SECTIONS_PRESENT_AT_BOOT */
		{
			k_heap_init(heap, heap->heap.init_mem, heap->heap.init_bytes);
		}
	}
	return 0;
}

SYS_INIT_NAMED(statics_init_pre, statics_init, PRE_KERNEL_1, CONFIG_KERNEL_INIT_PRIORITY_OBJECTS);

#if defined(CONFIG_DEMAND_PAGING) && !defined(CONFIG_LINKER_GENERIC_SECTIONS_PRESENT_AT_BOOT)
/* Need to wait for paging mechanism to be initialized before
 * heaps that are not in pinned sections can be initialized.
 */
SYS_INIT_NAMED(statics_init_post, statics_init, POST_KERNEL, 0);
#endif /* CONFIG_DEMAND_PAGING && !CONFIG_LINKER_GENERIC_SECTIONS_PRESENT_AT_BOOT */

void *k_heap_aligned_alloc(struct k_heap *heap, size_t align, size_t bytes,
			k_timeout_t timeout)
{
	k_timepoint_t end = sys_timepoint_calc(timeout);
	void *ret = NULL;

	k_spinlock_key_t key = k_spin_lock(&heap->lock);

	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_heap, aligned_alloc, heap, timeout);

	__ASSERT(!arch_is_in_isr() || K_TIMEOUT_EQ(timeout, K_NO_WAIT), "");

	bool blocked_alloc = false;

	while (ret == NULL) {
		ret = sys_heap_aligned_alloc(&heap->heap, align, bytes);

		if (!IS_ENABLED(CONFIG_MULTITHREADING) ||
		    (ret != NULL) || K_TIMEOUT_EQ(timeout, K_NO_WAIT)) {
			break;
		}

		if (!blocked_alloc) {
			blocked_alloc = true;

			SYS_PORT_TRACING_OBJ_FUNC_BLOCKING(k_heap, aligned_alloc, heap, timeout);
		} else {
			/**
			 * @todo	Trace attempt to avoid empty trace segments
			 */
		}

		timeout = sys_timepoint_timeout(end);
		(void) z_pend_curr(&heap->lock, key, &heap->wait_q, timeout);
		key = k_spin_lock(&heap->lock);
	}

	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_heap, aligned_alloc, heap, timeout, ret);

	k_spin_unlock(&heap->lock, key);
	return ret;
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void *, __skadi_heap_aligned_alloc, struct k_heap *heap, size_t align, size_t bytes, k_timeout_t timeout)
		return k_heap_aligned_alloc(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_HEAP, struct k_heap, heap), align, bytes, timeout);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_heap_aligned_alloc)
#endif

void *k_heap_alloc(struct k_heap *heap, size_t bytes, k_timeout_t timeout)
{
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_heap, alloc, heap, timeout);

	void *ret = k_heap_aligned_alloc(heap, sizeof(void *), bytes, timeout);

	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_heap, alloc, heap, timeout, ret);

	return ret;
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void *, __skadi_heap_alloc, struct k_heap *heap, size_t bytes, k_timeout_t timeout)
		return k_heap_alloc(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_HEAP, struct k_heap, heap), bytes, timeout);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_heap_alloc)
#endif

void *k_heap_realloc(struct k_heap *heap, void *ptr, size_t bytes, k_timeout_t timeout)
{
	k_timepoint_t end = sys_timepoint_calc(timeout);
	void *ret = NULL;

	k_spinlock_key_t key = k_spin_lock(&heap->lock);

	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_heap, realloc, heap, ptr, bytes, timeout);

	__ASSERT(!arch_is_in_isr() || K_TIMEOUT_EQ(timeout, K_NO_WAIT), "");

	while (ret == NULL) {
		ret = sys_heap_aligned_realloc(&heap->heap, ptr, sizeof(void *), bytes);

		if (!IS_ENABLED(CONFIG_MULTITHREADING) ||
		    (ret != NULL) || K_TIMEOUT_EQ(timeout, K_NO_WAIT)) {
			break;
		}

		timeout = sys_timepoint_timeout(end);
		(void) z_pend_curr(&heap->lock, key, &heap->wait_q, timeout);
		key = k_spin_lock(&heap->lock);
	}

	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_heap, realloc, heap, ptr, bytes, timeout, ret);

	k_spin_unlock(&heap->lock, key);
	return ret;
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void *, __skadi_heap_realloc, struct k_heap *heap, void *ptr, size_t bytes, k_timeout_t timeout)
		return k_heap_realloc(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_HEAP, struct k_heap, heap), ptr, bytes, timeout);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_heap_realloc)
#endif

void k_heap_free(struct k_heap *heap, void *mem)
{
	k_spinlock_key_t key = k_spin_lock(&heap->lock);

	sys_heap_free(&heap->heap, mem);

	SYS_PORT_TRACING_OBJ_FUNC(k_heap, free, heap);
	if (IS_ENABLED(CONFIG_MULTITHREADING) && (z_unpend_all(&heap->wait_q) != 0)) {
		z_reschedule(&heap->lock, key);
	} else {
		k_spin_unlock(&heap->lock, key);
	}
}
#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_heap_free, struct k_heap *heap, void *mem)
		return k_heap_free(SKADI_INTERFACE_WRAPPER_TRANSLATE(SKADI_HEAP, struct k_heap, heap), mem);
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_heap_free)
#endif

#ifdef CONFIG_SKADI_LOADER
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_heap_cleanup, struct k_heap *heap){
		SKADI_INTERFACE_WRAPPER_REMOVE(SKADI_HEAP, heap);
	}
	SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_heap_cleanup)
#endif


#if defined(CONFIG_SKADI_LOADER) && !defined(SKADI_SUBSYSTEM)

/* not compiled into subsystem - need to manually init the trampolines */
__boot_func static int kheap_init_trampolines(void){
    bool init_ok = true;

	init_ok &= __skadi_heap_init_register_init_function();
	init_ok &= __skadi_heap_aligned_alloc_register_init_function();
	init_ok &= __skadi_heap_alloc_register_init_function();
	init_ok &= __skadi_heap_realloc_register_init_function();
	init_ok &= __skadi_heap_free_register_init_function();
	
    return init_ok == true ? 0 : -ENOMEM;
}

SYS_INIT(kheap_init_trampolines, PRE_KERNEL_1, CONFIG_LOADER_SKADI_TRAMPOLINE_INIT_PRIO);

#endif /* SKADI_SUBSYSTEM */
