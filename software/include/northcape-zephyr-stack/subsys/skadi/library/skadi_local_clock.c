#include <time.h>
#include <zephyr/posix/time.h>
#include <zephyr/posix/sys/time.h>
#include <zephyr/sys_clock.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_sched.h>

int skadi_clock_gettime(clockid_t clock, struct timespec *ts){
    uint64_t current_cycles = skadi_sys_clock_cycle_get_64();
    uint64_t secs = current_cycles / CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC;
    uint64_t remaining_cycles = current_cycles - (secs * CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC);
    uint64_t nsecs = (remaining_cycles / (CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC / USEC_PER_SEC)) * NSEC_PER_USEC;
    ts->tv_sec = secs;
    ts->tv_nsec = nsecs;

    BUILD_ASSERT(CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC >= USEC_PER_SEC);

    if(clock == CLOCK_REALTIME){
        return 0;
    }

    errno = EINVAL;

    return -1;
}

int skadi_gettimeofday(struct timeval *tv, void *tz)
{
	struct timespec ts;
	int res;

	/* As per POSIX, "if tzp is not a null pointer, the behavior
	 * is unspecified."  "tzp" is the "tz" parameter above. */
	ARG_UNUSED(tz);

	res = skadi_clock_gettime(CLOCK_REALTIME, &ts);
	tv->tv_sec = ts.tv_sec;
	tv->tv_usec = ts.tv_nsec / NSEC_PER_USEC;

	return res;
}

#define SKADI_SYS_CLOCK_CYC_PER_TICK (int64_t)(sys_clock_hw_cycles_per_sec() / CONFIG_SYS_CLOCK_TICKS_PER_SEC)


int64_t skadi_sys_clock_tick_get(void){
    return skadi_sys_clock_cycle_get_64() / SKADI_SYS_CLOCK_CYC_PER_TICK;
}
