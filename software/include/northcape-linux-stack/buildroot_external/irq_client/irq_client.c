#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <string.h>
#include <sys/param.h>

#include <signal.h>

#include <nc_benchmark.h>
#include <timer_ioctl.h>

#define TIMER_NAME "/dev/pulp_timer0"

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

#ifdef CONFIG_DEBUG
#define LOG_DBG(FMT,...) printf("[Debug] "FMT"\n" __VA_OPT__(,) __VA_ARGS__)
#else
#define LOG_DBG(FMT,...)
#endif

#define LOG_INF(FMT,...) printf("[Inf  ] "FMT"\n" __VA_OPT__(,) __VA_ARGS__)
#define LOG_WRN(FMT,...) fprintf(stderr,"[Warn ] "FMT"\n" __VA_OPT__(,) __VA_ARGS__)
#define LOG_ERR(FMT,...) fprintf(stderr,"[Err  ] "FMT"\n" __VA_OPT__(,) __VA_ARGS__)

static int64_t irq_delays[NUMBER_IRQS];

static uint32_t last_deadline;

static int irqs_completed = 0;

static int irq_wait_cycles = IRQ_WAIT_CYCLES;

#define ERR_EXIT(FMT,...) LOG_ERR(FMT __VA_OPT__(,) __VA_ARGS__); exit(1)

static inline uint64_t pulp_apb_timer_time_to_ns(int pulp_timer_fd, uint64_t time){
	uint64_t ret = time;

	int err = ioctl(pulp_timer_fd, IOCTL_TO_NS, &ret);

	if(err){
		ERR_EXIT("ioctl error %d", ret);
	}

	return ret;
}


static uint64_t pulp_apb_timer_get_current_time(int pulp_timer_fd){
	uint32_t current_time;
	int ret = read(pulp_timer_fd, &current_time, sizeof(current_time));

	if(ret < 0){
		ERR_EXIT("read: %s", strerror(errno));
	}

	return current_time;
}

static void pulp_apb_timer_schedule_compare_callback(int pulp_timer_fd, uint32_t set_time){
	if(write(pulp_timer_fd, &set_time, sizeof(set_time)) < 0){
		ERR_EXIT("write: %s", strerror(errno));
	}
}

int pulp_timer;

static void timer_callback(int sig_num)
{
	int *completed_irq_num = &irqs_completed;
	uint32_t current_time;

	if(sig_num != SIGIO){
		ERR_EXIT("Unknown signal %d", sig_num);
	}


	/* make sure there is no undercount */
	current_time = pulp_apb_timer_get_current_time(pulp_timer);

	irq_delays[*completed_irq_num] = current_time - last_deadline;
	irq_delays[*completed_irq_num] = pulp_apb_timer_time_to_ns(pulp_timer, irq_delays[*completed_irq_num]);

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
		nc_benchmark_evaluate_samples(irq_delays, NUMBER_IRQS, 0, buffer);
		exit(0);
	}

	LOG_DBG("Scheduling callback %u at %"PRIu32"!\n",*completed_irq_num,current_time);

	pulp_apb_timer_schedule_compare_callback(pulp_timer, current_time);

	LOG_DBG("Scheduled callback - returning to caller!");
}

static int pulp_apb_timer_get_first_device(void){
	return open(TIMER_NAME, O_RDWR);
}
/* so it is not optimized away */
static volatile int dummy_int;

#define BUSY_WAITER_PRINT_DELAY 16384

static int busy_waiter_start(void){
	dummy_int = 0;
    for(;;){
        if(dummy_int % BUSY_WAITER_PRINT_DELAY == 0){
            LOG_DBG("Busy waiting %d!\n", dummy_int);
        }
        dummy_int++;
    }
	return 0;
}

int main(void)
{
	uint32_t current_time;
	struct sigaction sa;

	sa.sa_handler =  timer_callback;
	sa.sa_flags = SA_RESTART;
	sigemptyset(&sa.sa_mask);
	sigaddset(&sa.sa_mask, SIGIO);
	
	if(sigaction(SIGIO, &sa, NULL) == -1){
		ERR_EXIT("Could not set sigaction: %s", strerror(errno));
	}

	pulp_timer = pulp_apb_timer_get_first_device();

	if(pulp_timer == -1){
		ERR_EXIT("open: %s - did you modprobe() the driver?", strerror(errno));
	}

	current_time = pulp_apb_timer_get_current_time(pulp_timer);

	current_time += irq_wait_cycles;

	last_deadline = current_time;

	LOG_INF("Scheduling timer interrupts!");

	pulp_apb_timer_schedule_compare_callback(pulp_timer, current_time);

	LOG_INF("Waiting for last callback!\n");

	return busy_waiter_start();
}
