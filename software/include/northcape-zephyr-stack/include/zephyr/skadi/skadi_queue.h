#ifndef SKADI_QUEUE_H
#define SKADI_QUEUE_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

#define SKADI_QUEUE_ASSERT(QUEUE, FILE, LINE) \
	__ASSERT(QUEUE, "Queue is null at %s:%d", FILE, LINE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_queue_init, struct k_queue *queue);

static inline void _skadi_queue_init(struct k_queue *queue, const char *file, const int line){

	SKADI_QUEUE_ASSERT(queue, file, line);
	__skadi_queue_init(queue);
}

#define skadi_queue_init(QUEUE) _skadi_queue_init(QUEUE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_queue_cancel_wait, struct k_queue *queue);

static inline void _skadi_queue_cancel_wait(struct k_queue *queue, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__skadi_queue_cancel_wait(queue);
}

#define skadi_queue_cancel_wait(QUEUE) _skadi_queue_cancel_wait(QUEUE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_queue_alloc_append, struct k_queue *queue, void *data);

static inline int _skadi_queue_alloc_append(struct k_queue *queue, void *data, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	return __skadi_queue_alloc_append(queue, data);
}

#define skadi_queue_alloc_append(QUEUE, DATA) _skadi_queue_alloc_append(QUEUE, DATA, __FILE__, __LINE__)

/* would have to reveal the data otherwise */
#define skadi_queue_append(QUEUE, DATA) _skadi_queue_alloc_append(QUEUE, DATA, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_queue_alloc_prepend, struct k_queue *queue, void *data);

static inline int _skadi_queue_alloc_prepend(struct k_queue *queue, void *data, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	return __skadi_queue_alloc_prepend(queue, data);
}

#define skadi_queue_alloc_prepend(QUEUE, DATA) _skadi_queue_alloc_prepend(QUEUE, DATA, __FILE__, __LINE__)

/* would have to reveal the data otherwise*/
#define skadi_queue_prepend(QUEUE, DATA) _skadi_queue_alloc_prepend(QUEUE, DATA, __FILE__, __LINE__)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_queue_alloc_insert, struct k_queue *queue, void *prev, void *data);

static inline void _skadi_queue_alloc_insert(struct k_queue *queue, void *prev, void *data, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	__skadi_queue_alloc_insert(queue, prev, data);
}
/* otherwise, would reveal the data */
#define skadi_queue_insert(QUEUE, PREV, DATA) _skadi_queue_alloc_insert(QUEUE, PREV, DATA, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_queue_append_list, struct k_queue *queue, void *head, void *tail);

static inline int _skadi_queue_append_list(struct k_queue *queue, void *head, void *tail, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	return __skadi_queue_append_list(queue, head, tail);
}

#define skadi_queue_append_list(QUEUE, HEAD, TAIL) _skadi_queue_append_list(QUEUE, HEAD, TAIL, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_queue_merge_slist, struct k_queue *queue, sys_slist_t *list);

static inline int _skadi_queue_merge_slist(struct k_queue *queue, sys_slist_t *list, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	return __skadi_queue_merge_slist(queue, list);
}

#define skadi_queue_merge_slist(QUEUE, LIST) _skadi_queue_merge_slist(QUEUE, LIST, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void *, __skadi_queue_get, struct k_queue *queue, k_timeout_t timeout);

static inline void * _skadi_queue_get(struct k_queue *queue, k_timeout_t timeout, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	return __skadi_queue_get(queue, timeout);
}

#define skadi_queue_get(QUEUE, TIMEOUT) _skadi_queue_get(QUEUE, TIMEOUT, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, __skadi_queue_remove, struct k_queue *queue, void *data);

static inline bool _skadi_queue_remove(struct k_queue *queue, void *data, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	return __skadi_queue_remove(queue, data);
}

#define skadi_queue_remove(QUEUE, DATA) _skadi_queue_remove(QUEUE, DATA, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, __skadi_queue_alloc_unique_append, struct k_queue *queue, void *data);

static inline bool _skadi_queue_alloc_unique_append(struct k_queue *queue, void *data, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	return __skadi_queue_alloc_unique_append(queue, data);
}

#define skadi_queue_alloc_unique_append(QUEUE, DATA) _skadi_queue_alloc_unique_append(QUEUE, DATA, __FILE__, __LINE__)

/* would have to reveal the data otherwise */
#define skadi_queue_unique_append(QUEUE, DATA) _skadi_queue_alloc_unique_append(QUEUE, DATA, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void *, __skadi_queue_peek_head, struct k_queue *queue);

static inline void *_skadi_queue_peek_head(struct k_queue *queue, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	return __skadi_queue_peek_head(queue);
}

#define skadi_queue_peek_head(QUEUE) _skadi_queue_peek_head(QUEUE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void *, __skadi_queue_peek_tail, struct k_queue *queue);

static inline void *_skadi_queue_peek_tail(struct k_queue *queue, const char *file, const int line){
	SKADI_QUEUE_ASSERT(queue, file, line);

	__ASSERT_NO_MSG(queue);
	return __skadi_queue_peek_tail(queue);
}

#define skadi_queue_peek_tail(QUEUE) _skadi_queue_peek_tail(QUEUE, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, __skadi_queue_is_empty, struct k_queue *queue);

#define skadi_queue_is_empty(ARG) __skadi_queue_is_empty(ARG)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_queue_cleanup, struct k_queue *queue);

static inline void skadi_queue_cleanup(struct k_queue *queue){
	__skadi_queue_cleanup(queue);
}

/**
 * @brief Initialize a FIFO queue.
 *
 * This routine initializes a FIFO queue, prior to its first use.
 *
 * @param fifo Address of the FIFO queue.
 */
#define skadi_fifo_init(fifo)                        \
	({                                                   \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_fifo, init, fifo); \
	skadi_queue_init(&(fifo)->_queue);               \
	K_OBJ_CORE_INIT(K_OBJ_CORE(fifo), _obj_type_fifo);   \
	K_OBJ_CORE_LINK(K_OBJ_CORE(fifo));                   \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_fifo, init, fifo);  \
	})

/**
 * @brief Cancel waiting on a FIFO queue.
 *
 * This routine causes first thread pending on @a fifo, if any, to
 * return from skadi_fifo_get() call with NULL value (as if timeout
 * expired).
 *
 * @funcprops \isr_ok
 *
 * @param fifo Address of the FIFO queue.
 */
#define skadi_fifo_cancel_wait(fifo) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(skadi_fifo, cancel_wait, fifo); \
	skadi_queue_cancel_wait(&(fifo)->_queue); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(skadi_fifo, cancel_wait, fifo); \
	})

/**
 * @brief Add an element to a FIFO queue.
 *
 * This routine adds a data item to @a fifo. A FIFO data item must be
 * aligned on a word boundary, and the first word of the item is reserved
 * for the kernel's use.
 *
 * @funcprops \isr_ok
 *
 * @param fifo Address of the FIFO.
 * @param data Address of the data item.
 */
#define skadi_fifo_put(fifo, data) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_fifo, put, fifo, data); \
	skadi_queue_append(&(fifo)->_queue, data); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_fifo, put, fifo, data); \
	})

/**
 * @brief Add an element to a FIFO queue.
 *
 * This routine adds a data item to @a fifo. There is an implicit memory
 * allocation to create an additional temporary bookkeeping data structure from
 * the calling thread's resource pool, which is automatically freed when the
 * item is removed. The data itself is not copied.
 *
 * @funcprops \isr_ok
 *
 * @param fifo Address of the FIFO.
 * @param data Address of the data item.
 *
 * @retval 0 on success
 * @retval -ENOMEM if there isn't sufficient RAM in the caller's resource pool
 */
#define skadi_fifo_alloc_put(fifo, data) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_fifo, alloc_put, fifo, data); \
	int fap_ret = skadi_queue_alloc_append(&(fifo)->_queue, data); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_fifo, alloc_put, fifo, data, fap_ret); \
	fap_ret; \
	})

/**
 * @brief Atomically add a list of elements to a FIFO.
 *
 * This routine adds a list of data items to @a fifo in one operation.
 * The data items must be in a singly-linked list, with the first word of
 * each data item pointing to the next data item; the list must be
 * NULL-terminated.
 *
 * @funcprops \isr_ok
 *
 * @param fifo Address of the FIFO queue.
 * @param head Pointer to first node in singly-linked list.
 * @param tail Pointer to last node in singly-linked list.
 */
#define skadi_fifo_put_list(fifo, head, tail) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_fifo, put_list, fifo, head, tail); \
	skadi_queue_append_list(&(fifo)->_queue, head, tail); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_fifo, put_list, fifo, head, tail); \
	})

/**
 * @brief Atomically add a list of elements to a FIFO queue.
 *
 * This routine adds a list of data items to @a fifo in one operation.
 * The data items must be in a singly-linked list implemented using a
 * sys_slist_t object. Upon completion, the sys_slist_t object is invalid
 * and must be re-initialized via sys_slist_init().
 *
 * @funcprops \isr_ok
 *
 * @param fifo Address of the FIFO queue.
 * @param list Pointer to sys_slist_t object.
 */
#define skadi_fifo_put_slist(fifo, list) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_fifo, put_slist, fifo, list); \
	skadi_queue_merge_slist(&(fifo)->_queue, list); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_fifo, put_slist, fifo, list); \
	})

/**
 * @brief Get an element from a FIFO queue.
 *
 * This routine removes a data item from @a fifo in a "first in, first out"
 * manner. The first word of the data item is reserved for the kernel's use.
 *
 * @note @a timeout must be set to K_NO_WAIT if called from ISR.
 *
 * @funcprops \isr_ok
 *
 * @param fifo Address of the FIFO queue.
 * @param timeout Waiting period to obtain a data item,
 *                or one of the special values K_NO_WAIT and K_FOREVER.
 *
 * @return Address of the data item if successful; NULL if returned
 * without waiting, or waiting period timed out.
 */
#define skadi_fifo_get(fifo, timeout) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_fifo, get, fifo, timeout); \
	void *fg_ret = skadi_queue_get(&(fifo)->_queue, timeout); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_fifo, get, fifo, timeout, fg_ret); \
	fg_ret; \
	})

/**
 * @brief Query a FIFO queue to see if it has data available.
 *
 * Note that the data might be already gone by the time this function returns
 * if other threads is also trying to read from the FIFO.
 *
 * @funcprops \isr_ok
 *
 * @param fifo Address of the FIFO queue.
 *
 * @return Non-zero if the FIFO queue is empty.
 * @return 0 if data is available.
 */
#define skadi_fifo_is_empty(fifo) \
	skadi_queue_is_empty(&(fifo)->_queue)

/**
 * @brief Peek element at the head of a FIFO queue.
 *
 * Return element from the head of FIFO queue without removing it. A usecase
 * for this is if elements of the FIFO object are themselves containers. Then
 * on each iteration of processing, a head container will be peeked,
 * and some data processed out of it, and only if the container is empty,
 * it will be completely remove from the FIFO queue.
 *
 * @param fifo Address of the FIFO queue.
 *
 * @return Head element, or NULL if the FIFO queue is empty.
 */
#define skadi_fifo_peek_head(fifo) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_fifo, peek_head, fifo); \
	void *fph_ret = skadi_queue_peek_head(&(fifo)->_queue); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_fifo, peek_head, fifo, fph_ret); \
	fph_ret; \
	})

/**
 * @brief Peek element at the tail of FIFO queue.
 *
 * Return element from the tail of FIFO queue (without removing it). A usecase
 * for this is if elements of the FIFO queue are themselves containers. Then
 * it may be useful to add more data to the last container in a FIFO queue.
 *
 * @param fifo Address of the FIFO queue.
 *
 * @return Tail element, or NULL if a FIFO queue is empty.
 */
#define skadi_fifo_peek_tail(fifo) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_fifo, peek_tail, fifo); \
	void *fpt_ret = skadi_queue_peek_tail(&(fifo)->_queue); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_fifo, peek_tail, fifo, fpt_ret); \
	fpt_ret; \
	})

#define skadi_fifo_cleanup(fifo) \
	skadi_queue_cleanup(&(fifo)->_queue)

/**
 * @brief Initialize a LIFO queue.
 *
 * This routine initializes a LIFO queue object, prior to its first use.
 *
 * @param lifo Address of the LIFO queue.
 */
#define skadi_lifo_init(lifo)                                    \
	({                                                   \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_lifo, init, lifo); \
	skadi_queue_init(&(lifo)->_queue);               \
	K_OBJ_CORE_INIT(K_OBJ_CORE(lifo), _obj_type_lifo);   \
	K_OBJ_CORE_LINK(K_OBJ_CORE(lifo));                   \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_lifo, init, lifo);  \
	})

/**
 * @brief Add an element to a LIFO queue.
 *
 * This routine adds a data item to @a lifo. A LIFO queue data item must be
 * aligned on a word boundary, and the first word of the item is
 * reserved for the kernel's use.
 *
 * @funcprops \isr_ok
 *
 * @param lifo Address of the LIFO queue.
 * @param data Address of the data item.
 */
#define skadi_lifo_put(lifo, data) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_lifo, put, lifo, data); \
	skadi_queue_prepend(&(lifo)->_queue, data); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_lifo, put, lifo, data); \
	})

/**
 * @brief Add an element to a LIFO queue.
 *
 * This routine adds a data item to @a lifo. There is an implicit memory
 * allocation to create an additional temporary bookkeeping data structure from
 * the calling thread's resource pool, which is automatically freed when the
 * item is removed. The data itself is not copied.
 *
 * @funcprops \isr_ok
 *
 * @param lifo Address of the LIFO.
 * @param data Address of the data item.
 *
 * @retval 0 on success
 * @retval -ENOMEM if there isn't sufficient RAM in the caller's resource pool
 */
#define skadi_lifo_alloc_put(lifo, data) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_lifo, alloc_put, lifo, data); \
	int lap_ret = skadi_queue_alloc_prepend(&(lifo)->_queue, data); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_lifo, alloc_put, lifo, data, lap_ret); \
	lap_ret; \
	})

/**
 * @brief Get an element from a LIFO queue.
 *
 * This routine removes a data item from @a LIFO in a "last in, first out"
 * manner. The first word of the data item is reserved for the kernel's use.
 *
 * @note @a timeout must be set to K_NO_WAIT if called from ISR.
 *
 * @funcprops \isr_ok
 *
 * @param lifo Address of the LIFO queue.
 * @param timeout Waiting period to obtain a data item,
 *                or one of the special values K_NO_WAIT and K_FOREVER.
 *
 * @return Address of the data item if successful; NULL if returned
 * without waiting, or waiting period timed out.
 */
#define skadi_lifo_get(lifo, timeout) \
	({ \
	SYS_PORT_TRACING_OBJ_FUNC_ENTER(k_lifo, get, lifo, timeout); \
	void *lg_ret = skadi_queue_get(&(lifo)->_queue, timeout); \
	SYS_PORT_TRACING_OBJ_FUNC_EXIT(k_lifo, get, lifo, timeout, lg_ret); \
	lg_ret; \
	})

#define skadi_lifo_cleanup(lifo) \
	skadi_queue_cleanup(&(lifo)->_queue)



#endif /* SKADI_SUBSYSTEM */

extern void skadi_subsystem_yield(void);
#endif /* SKADI_QUEUE_H */
