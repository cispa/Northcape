
#include <cv64a6.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(skadi_irq_test_client, CONFIG_SKADI_SUBSYSTEM_LOG_LEVEL);

#ifdef CONFIG_SKADI_LOADER
#include <zephyr/skadi/subsystems/pulp_apb_timer/pulp_apb_timer.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_sched.h>
#else
#include <zephyr/drivers/timer/pulp_apb_timer.h>
#define SKADI_SUBSYSTEM_FUNCTION_POINTER(ARG) ARG
#endif

#include <zephyr/skadi/skadi_benchmark.h>

#include <zephyr/arch/riscv/csr.h>



#define NUMBER_IRQS 100
/* 
 * for rate benchmark, start super low to approach critical rate from below
 * for latency benchmark, use a high wait time to minimize change of immediate interrupt
 */
#ifdef CONFIG_TIMER_IRQ_SAMPLE_BENCHMARK_RATE
#define IRQ_WAIT_CYCLES 100
/* until where to jump */
#define IRQ_WAIT_CYCLES_THRESHOLD 10000
#else
#define IRQ_WAIT_CYCLES 10000000
#endif

static struct skadi_benchmark_state irq_delays[NUMBER_IRQS];

static uint32_t last_deadline;

static int irqs_completed = 0;

static int irq_wait_cycles = IRQ_WAIT_CYCLES;

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(bool, timer_callback, const struct device *pulp_timer, uint32_t current_time, void *cookie)
#else
static bool timer_callback(const struct device *pulp_timer, uint32_t current_time, void *cookie)
#endif
{
	int *completed_irq_num = &irqs_completed;
	int64_t elapsed_time;

	ARG_UNUSED(cookie);

	/* make sure there is no undercount */
	current_time = pulp_apb_timer_get_current_time(pulp_timer);

	elapsed_time = current_time - last_deadline;
	elapsed_time = pulp_apb_timer_time_to_ns(pulp_timer, elapsed_time);

	skadi_benchmark_add_sample(&irq_delays[*completed_irq_num], elapsed_time);

	if((*completed_irq_num) + 1 < NUMBER_IRQS){
		skadi_benchmark_prepare_sample(&irq_delays[(*completed_irq_num)+1]);
	}

	LOG_DBG("Callback %u called at time %"PRIu32" with deadline %"PRIu32"!\n",*completed_irq_num,current_time, last_deadline);

	if(current_time < last_deadline){
		LOG_WRN("Callback %u called too early at time %"PRIu32" with deadline %"PRIu32"!\n",*completed_irq_num,current_time, last_deadline);
	}

#ifdef CONFIG_TIMER_IRQ_SAMPLE_BENCHMARK_RATE
	if(current_time >= last_deadline + irq_wait_cycles){
		// prevent jump too far over the critical rate...
		int addend;
		
		addend = MAX((current_time - last_deadline)/8, IRQ_WAIT_CYCLES);

		if(addend < IRQ_WAIT_CYCLES_THRESHOLD){
			addend = IRQ_WAIT_CYCLES;
		}
			
		LOG_WRN("Deadline missed for %u cycles (called at %"PRIu32" with deadline %"PRIu32") - increasing by %u!", irq_wait_cycles, current_time, last_deadline, addend);
		/* increase dealine and try again */
		irq_wait_cycles += addend;
		*completed_irq_num = 0;
		current_time = pulp_apb_timer_get_current_time(pulp_timer);
	}
	else{
		/* continue from last deadline */
		current_time = last_deadline;
	}
#endif
	current_time += irq_wait_cycles;

	last_deadline = current_time;

	*completed_irq_num = *completed_irq_num + 1;

	if(*completed_irq_num == NUMBER_IRQS){
		char buffer[100];

		LOG_INF("Test success!\n");

		snprintf(buffer, sizeof(buffer), "IRQ delays for rate %"PRIu64" (%"PRIu32" cycles)", pulp_apb_timer_time_to_ns(pulp_timer, irq_wait_cycles), irq_wait_cycles);
		buffer[sizeof(buffer)-1]='\0';
#ifdef CONFIG_SKADI_LOADER
		skadi_benchmark_evaluate_samples(irq_delays, NUMBER_IRQS, 0, skadi_cap_ops_derive_arg_ro(buffer, sizeof(buffer)));
#else
		skadi_benchmark_evaluate_samples(irq_delays, NUMBER_IRQS, 0, buffer);
#endif
		z_cv64a6_finish_test(0);
	}

	LOG_DBG("Scheduling callback %u at %"PRIu32"!\n",*completed_irq_num,current_time);

	pulp_apb_timer_schedule_compare_callback(pulp_timer, current_time, SKADI_SUBSYSTEM_FUNCTION_POINTER(timer_callback), &irqs_completed);

	LOG_DBG("Scheduled callback - returning to caller!");
	
	return false;
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(timer_callback)
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, busy_waiter_start, void);
#else
extern int busy_waiter_start(void);
#endif


#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(bool, irq_client_start_test, void)
#else
bool irq_client_start_test(void)
#endif
{
    const struct device *pulp_timer = pulp_apb_timer_get_first_device();
	uint32_t current_time;

#ifdef CONFIG_TIMER_NMI
	LOG_INF("Making IRQ mask %x unmaskeable!\n", MIP_MEIP);
	skadi_cv64a6_make_interrupt_unmaskeable(MIP_MEIP);
	LOG_INF("Reading back IRQ mask %lx!", csr_read(0x7cd));
#endif

	current_time = pulp_apb_timer_get_current_time(pulp_timer);

	if(current_time != 0){
		LOG_INF("Current time expected to be 0 initially but is %"PRIu32"\n", current_time);
		return false;
	}

	current_time += irq_wait_cycles;

	last_deadline = current_time;

	LOG_INF("Scheduling timer interrupts!");

	skadi_benchmark_prepare_sample(&irq_delays[0]);

	pulp_apb_timer_schedule_compare_callback(pulp_timer, current_time, SKADI_SUBSYSTEM_FUNCTION_POINTER(timer_callback), &irqs_completed);

#ifdef CONFIG_TIMER_NMI
	// disable interrupts earlier
	(void)arch_irq_lock();
#endif

	LOG_INF("Waiting for last callback!\n");

	return busy_waiter_start();
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(irq_client_start_test)
#endif
