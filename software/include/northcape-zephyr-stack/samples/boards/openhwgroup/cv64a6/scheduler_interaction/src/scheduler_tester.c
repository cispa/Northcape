/**
 * Provides a subsytem that tests the dummy encrypt subsystem.
 */

#include <zephyr/logging/log.h>
#include <zephyr/kernel.h>
#include <zephyr/llext/symbol.h>

LOG_MODULE_REGISTER(skadi_dummy_subsystem_consumer, CONFIG_LOG_DEFAULT_LEVEL);

#include <cv64a6.h>

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_sched.h>
#include <zephyr/skadi/skadi_work.h>
#include <zephyr/skadi/skadi_mem_slab.h>
#include <zephyr/skadi/skadi_sem.h>
#include <zephyr/skadi/skadi_mutex.h>
#include <zephyr/skadi/skadi_heap.h>
#include <zephyr/skadi/skadi_msg_queue.h>
#include <zephyr/skadi/skadi_queue.h>
#include <zephyr/skadi/skadi_timer.h>
#include <zephyr/skadi/skadi_pipe.h>

#define WORKQUEUE_USER 0xfeedbeefdeadbeef
#define TIMER_USER	   0xdeaddeadbeefbeef

#define TEST_MESSAGE_QUEUE_MESSAGE			"foo"
#define TEST_MESSAGE_QUEUE_MESSAGE_SIZE 	(sizeof(TEST_MESSAGE_QUEUE_MESSAGE))
#define TEST_MESSAGE_QUEUE_MAX_MESSAGES		2

struct dummy_queue_data {
	sys_sfnode_t list_node;
	const char *dummy_data;
};

volatile bool thread_test_ok;
volatile bool workqueue_test_ok;
volatile bool timer_test_ok;
volatile bool yield_test_ok;
volatile bool sem_put_ok;
volatile bool sem_get_ok;
volatile bool mem_alloc_ok;
volatile bool mem_free_ok;

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void, skadi_subsystem_test_test_ok, bool val);

static inline void report_test_ok(void){
	skadi_subsystem_test_test_ok(thread_test_ok && workqueue_test_ok && timer_test_ok && yield_test_ok && sem_put_ok && sem_get_ok && mem_alloc_ok && mem_free_ok);
}


SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, workqueue_handler, struct k_work *work)
	if(work->user_data != (void*)WORKQUEUE_USER){
		LOG_ERR("Incorrect work queue user: %p", work->user_data);
		return;
	}

	LOG_INF("Workqueue OK!");

	workqueue_test_ok = true;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(workqueue_handler)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, timer_exp_handler, struct k_timer *timer)
	if(skadi_timer_user_data_get(timer) != (void*)TIMER_USER){
		LOG_ERR("Incorrect timer user: %p", skadi_timer_user_data_get(timer));
		return;
	}

	LOG_INF("Timer OK!");

	timer_test_ok = true;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(timer_exp_handler)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, timer_stop_handler, struct k_timer *timer)
	if(skadi_timer_user_data_get(timer) != (void*)TIMER_USER){
		LOG_ERR("Incorrect timer user: %p", skadi_timer_user_data_get(timer));
		return;
	}

	LOG_INF("Timer stop OK!");

	report_test_ok();
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(timer_stop_handler)

static struct k_heap test_heap;
static void *heap_out;

static struct k_mutex test_mutex;

static struct k_msgq test_msgq;

static struct k_queue test_queue;

static struct k_timer timer;

static struct k_pipe pipe;

static struct dummy_queue_data dummy_queue_data = {.dummy_data = TEST_MESSAGE_QUEUE_MESSAGE};

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, test_thread_1_handler, void *p1, void *p2, void *p3)
{
	struct k_sem *synch = p1;
	void **memory = (void **) p2;
	struct k_mem_slab *slab = p3;
	size_t bytes_written;

	LOG_INF("Thread 1 launched!");

	thread_test_ok = true;

	/* dummy use, just to test the mutex */
	if(skadi_mutex_lock(&test_mutex, K_FOREVER) != 0){
		LOG_ERR("Could not lock mutex!");
		return;
	}

	skadi_subsystem_yield();

	if(skadi_mutex_unlock(&test_mutex) != 0){
		LOG_ERR("Could not unlock mutex!");
		return;
	}

	yield_test_ok = true;

	LOG_INF("Thread 1 yield OK!");

	
	if(skadi_mem_slab_alloc(slab, memory, K_FOREVER) != 0){
		LOG_ERR("skadi_mem_slab_alloc failed!");
		return;
	}

	if(skadi_msgq_put(&test_msgq, TEST_MESSAGE_QUEUE_MESSAGE, K_FOREVER) != 0){
		LOG_ERR("skadi_msgq_put failed!");
		return;
	}

	if(skadi_pipe_put(&pipe, TEST_MESSAGE_QUEUE_MESSAGE, TEST_MESSAGE_QUEUE_MESSAGE_SIZE, &bytes_written, TEST_MESSAGE_QUEUE_MESSAGE_SIZE, K_FOREVER) != 0 || bytes_written != TEST_MESSAGE_QUEUE_MESSAGE_SIZE){
		LOG_ERR("skadi_pipe_put failed!");
		return;
	}

	skadi_thread_heap_assign(skadi_current_get(), &test_heap);

	if(skadi_queue_alloc_append(&test_queue, TEST_MESSAGE_QUEUE_MESSAGE) != 0){
		LOG_ERR("skadi_queue_alloc_append failed!");
		return;
	}

	skadi_queue_append(&test_queue, &dummy_queue_data);

	if(skadi_queue_unique_append(&test_queue, &dummy_queue_data)){
		LOG_ERR("Unique append did NOT realize data are already present!");
		return;
	}

	LOG_INF("Thread 1 slab alloc ok!");

	if((heap_out = skadi_heap_alloc(&test_heap, sizeof(uintptr_t), K_FOREVER)) == NULL){
		LOG_ERR("skadi_heap_alloc failed!");
		return;
	}

	LOG_INF("Thread 1 heap alloc ok!");

	mem_alloc_ok = true;

	skadi_sem_give(synch);

	sem_put_ok = true;

	LOG_INF("Thread 1 complete!");

	report_test_ok();
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(test_thread_1_handler)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, test_thread_2_handler, void *p1, void *p2, void *p3)
{
	struct k_sem *synch = p1;
	void **memory = (void **) p2;
	struct k_mem_slab *slab = p3;
	void *queue_out;
	struct dummy_queue_data *dummy_queue_out;
	uint32_t timer_out;
	size_t bytes_read;

	char msgq_data_out[TEST_MESSAGE_QUEUE_MESSAGE_SIZE];
	char pipe_data_out[TEST_MESSAGE_QUEUE_MESSAGE_SIZE];

	LOG_INF("Thread 2 launched!");

	skadi_sleep(K_MSEC(10));

	LOG_INF("Thread 2 sleep OK!");

	timer_out = skadi_timer_status_sync(&timer);

	LOG_INF("Thread 2 sync timer OK with status %"PRIu32"!",timer_out);

	skadi_timer_stop(&timer);

	LOG_INF("Thread 2 timer stop OK!");

	if(skadi_sem_take(synch, K_FOREVER) != 0){
		LOG_ERR("Could not take semaphore!");
		return;
	}

	LOG_INF("Thread 2 sem OK!");

	/* dummy use, just to test the mutex */
	if(skadi_mutex_lock(&test_mutex, K_FOREVER) != 0){
		LOG_ERR("Could not lock mutex!");
		return;
	}

	LOG_INF("Thread 2 mutex OK!");

	if(skadi_msgq_get(&test_msgq, msgq_data_out, K_FOREVER) != 0){
		LOG_ERR("skadi_msgq_get failed!");
		return;
	}

	if(memcmp(msgq_data_out, TEST_MESSAGE_QUEUE_MESSAGE, TEST_MESSAGE_QUEUE_MESSAGE_SIZE) != 0){
		LOG_ERR("Returned wrong message %s!", (char *) msgq_data_out);
		return;
	}

	if(skadi_pipe_get(&pipe, pipe_data_out, TEST_MESSAGE_QUEUE_MESSAGE_SIZE, &bytes_read, TEST_MESSAGE_QUEUE_MESSAGE_SIZE, K_FOREVER) != 0 || bytes_read != TEST_MESSAGE_QUEUE_MESSAGE_SIZE){
		LOG_ERR("skadi_pipe_get failed!");
		return;
	}

	if(memcmp(pipe_data_out, TEST_MESSAGE_QUEUE_MESSAGE, TEST_MESSAGE_QUEUE_MESSAGE_SIZE) != 0){
		LOG_ERR("Returned wrong message %s!", pipe_data_out);
		return;
	}

	LOG_INF("Thread 2 msgq OK!");

	if((queue_out = skadi_queue_get(&test_queue, K_FOREVER)) == NULL){
		LOG_ERR("skadi_queue_get returned 0!");
		return;
	}

	if(memcmp(queue_out, TEST_MESSAGE_QUEUE_MESSAGE, TEST_MESSAGE_QUEUE_MESSAGE_SIZE) != 0){
		LOG_ERR("Returned wrong message %s!", (char *) msgq_data_out);
		return;
	}

	if((dummy_queue_out = skadi_queue_get(&test_queue, K_FOREVER)) == NULL){
		LOG_ERR("skadi_queue_get returned 0!");
		return;
	}

	if(dummy_queue_out != &dummy_queue_data){
		LOG_ERR("Returned wrong data %p", dummy_queue_out);
		return;
	}

	__ASSERT(skadi_queue_is_empty(&test_queue), "Expected queue to be empty!");

	LOG_INF("Thread 2 queue OK!");

	sem_get_ok = true;

	skadi_mem_slab_free(slab, *memory);

	LOG_INF("Thread 2 slab free OK!");

	skadi_heap_free(&test_heap, heap_out);

	LOG_INF("Thread 2 heap free OK!");

	if(skadi_mutex_unlock(&test_mutex) != 0){
		LOG_ERR("Could not unlock mutex!");
		return;
	}

	LOG_INF("Thread 2 unlock OK!");

	mem_free_ok = true;

	LOG_INF("Thread 2 complete!");

	report_test_ok();

}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(test_thread_2_handler)

static struct k_work test_work;
// this value is always 1 off
static const size_t stack_size =  CONFIG_SKADI_SUBSYSTEM_STACK_SIZE + 1;
K_KERNEL_STACK_DEFINE(test_thread_1_stack, CONFIG_SKADI_SUBSYSTEM_STACK_SIZE + 1);
K_KERNEL_STACK_DEFINE(test_thread_2_stack, CONFIG_SKADI_SUBSYSTEM_STACK_SIZE + 1);
static struct k_thread thread_1, thread_2;

static k_tid_t tid_1, tid_2;
static struct k_sem synch;
static void *memory;

K_MEM_SLAB_DEFINE_STATIC(mem_slab, 256, 4, 3);

#define TEST_HEAP_SIZE_BYTES 128
static char heap_mem[TEST_HEAP_SIZE_BYTES];

static char msgq_buffer[TEST_MESSAGE_QUEUE_MESSAGE_SIZE * TEST_MESSAGE_QUEUE_MAX_MESSAGES];

static char pipe_buffer[TEST_MESSAGE_QUEUE_MESSAGE_SIZE * TEST_MESSAGE_QUEUE_MAX_MESSAGES];

static int scheduler_tester_init(void){
	struct k_mem_slab *slab = &mem_slab;
	struct skadi_thread_create_params params;

	if(skadi_sem_init(&synch, 0, 1) != 0){
		LOG_ERR("Could not initialize semaphore!");
		return -ENOMEM;
	}

	/* some internal pointers, such as free list, buffer, wait q are not set (correctly) yet */
	if(skadi_mem_slab_init(slab, slab->buffer, slab->info.block_size, slab->info.num_blocks) != 0){
		LOG_ERR("Could not init slab!");
		return -EINVAL;
	}

	skadi_timer_init(&timer, SKADI_SUBSYSTEM_FUNCTION_POINTER(timer_exp_handler), SKADI_SUBSYSTEM_FUNCTION_POINTER(timer_stop_handler));

	skadi_msgq_init(&test_msgq, msgq_buffer, TEST_MESSAGE_QUEUE_MESSAGE_SIZE, TEST_MESSAGE_QUEUE_MAX_MESSAGES);

	skadi_pipe_init(&pipe, pipe_buffer, TEST_MESSAGE_QUEUE_MESSAGE_SIZE * TEST_MESSAGE_QUEUE_MAX_MESSAGES);

	skadi_queue_init(&test_queue);

	skadi_heap_init(&test_heap, heap_mem, TEST_HEAP_SIZE_BYTES);

	skadi_work_init(&test_work, SKADI_SUBSYSTEM_FUNCTION_POINTER(workqueue_handler));
	test_work.user_data = (void *)WORKQUEUE_USER;

    skadi_work_submit(&test_work);

	skadi_timer_user_data_set(&timer,(void*) TIMER_USER);

	skadi_timer_start(&timer, K_MSEC(1), K_MSEC(10));

	if(skadi_mutex_init(&test_mutex) != 0){
		LOG_ERR("Could not init mutex!");
		return -EINVAL;
	}

	params.new_thread = &thread_2;
	params.stack = test_thread_2_stack;
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(test_thread_2_handler);

	params.stack_size = stack_size;
	params.p1 = &synch;
	params.p2 = &memory;
	params.p3 = slab;
	params.prio =  0;
	params.options = 0;
	params.delay = K_NO_WAIT;
	
	/* consumer starts before the producer to force context switch */
	tid_2 = skadi_thread_create(&params);

	params.new_thread = &thread_1;
	params.stack = test_thread_1_stack;
	params.entry = SKADI_SUBSYSTEM_FUNCTION_POINTER(test_thread_1_handler);

	tid_1 = skadi_thread_create(&params);

	return 0;
}

SYS_INIT(scheduler_tester_init, APPLICATION, 0);
