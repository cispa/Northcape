/**
 * @file Provides a subsystem that can be used to compute a one-time pad encryption of a uint64_t.
 */
#include <stdint.h>

#include <cv64a6.h>

#include <zephyr/logging/log.h>
#include <zephyr/kernel.h>
#include <zephyr/timing/timing.h>
#include <zephyr/llext/symbol.h>

LOG_MODULE_REGISTER(skadi_dummy_subsystem_provider, CONFIG_LOG_DEFAULT_LEVEL);

#include <zephyr/skadi/skadi_ariane_genesysii.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_loader.h>

#include <zephyr/skadi/skadi_sched.h>

#include <zephyr/skadi/skadi_benchmark.h>

#include "dummy_encrypt_subsys.h"

struct subsystem_private_data{
    uint64_t otp_key;
};

static struct subsystem_private_data *subsystem_private_data;


SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(uint64_t, dummy_subsystem_encrypt, uint64_t plaintext)
{
    return plaintext ^ subsystem_private_data->otp_key;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(dummy_subsystem_encrypt)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(uint64_t, dummy_subsystem_encrypt_8_args, uint64_t plaintext, long a1, long a2, long a3, long a4, long a5, long a6, long a7)
{
    if(a1 == 1 && a2 == 2 && a3 == 3 && a4 == 4 && a5 == 5 && a6 == 6 && a7 == 7){
        return plaintext ^ subsystem_private_data->otp_key;
    }
    LOG_ERR("Wrong argument list - got a1 %ld a2 %ld a3 %ld a4 %ld a5 %ld a6 %ld a7 %ld", a1, a2, a3, a4, a5, a6, a7);
    return -1;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(dummy_subsystem_encrypt_8_args)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(uint64_t, __dummy_subsystem_encrypt_valist, uint64_t plaintext, va_list args)
{
    uintptr_t dummy_variadic_1;
    int dummy_variadic_2;
    uint16_t dummy_variadic_3;
    
    __ASSERT_NO_MSG(args);

    dummy_variadic_1 = va_arg(args, uintptr_t);
    dummy_variadic_2 = va_arg(args, int);
    dummy_variadic_3 = va_arg(args, unsigned int);

    if(dummy_variadic_1 != DUMMY_SUBSYSTEM_VARIADIC_1){
        LOG_ERR("Dummy variadic 1 wrong - got %p!",(void *) dummy_variadic_1);
        return 0;
    }

    if(dummy_variadic_2 != DUMMY_SUBSYSTEM_VARIADIC_2){
        LOG_ERR("Dummy variadic 2 wrong - got %x!", dummy_variadic_2);
        return 0;
    }

    if(dummy_variadic_3 != DUMMY_SUBSYSTEM_VARIADIC_3){
        LOG_ERR("Dummy variadic 3 wrong - got %"PRIx16"!", dummy_variadic_3);
        return 0;
    }

    return plaintext ^ subsystem_private_data->otp_key;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__dummy_subsystem_encrypt_valist)

static bool dummy_subsystem_encrypt_init(void){
    skadi_task_id_t my_task_id = SKADI_CURRENT_TASK_ID;
    void *restricted_private_data = NULL;
    bool alloc_ok;
    skadi_restriction_t restriction = SKADI_TASK_ID_BOUND_RESTRICTION(my_task_id,SKADI_DEVICE_ID_CPU);

    SKADI_INSTALL_TIME_INTERRUPT_HOOK;

    if(my_task_id == 0){
        LOG_ERR("Task ID has not been set!");
        z_cv64a6_finish_test(1);
    }

    subsystem_private_data = skadi_allocator_alloc_rw(sizeof(*subsystem_private_data));

    if(!subsystem_private_data){
        LOG_ERR("Could not allocate subsystem private data!");
        z_cv64a6_finish_test(1);
    }
    // write while we still have write permission
    subsystem_private_data->otp_key = DUMMY_SUBSYSTEM_OTP_KEY;

    // TODO this leaks the allocated memory
    alloc_ok = skadi_cap_ops_lock(subsystem_private_data, restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &restricted_private_data);

    if(!alloc_ok || !restricted_private_data){
        LOG_ERR("Could not lock capability for subsystem private data!");
        z_cv64a6_finish_test(1);
    }

    LOG_DBG("Have allocated task-locked secret data %"PRIx64,(uint64_t)restricted_private_data);

    // no one (not even the allocator or the DMA) can read the data + stack now, except the subsystem task

    subsystem_private_data = (struct subsystem_private_data *) restricted_private_data;

    return true;
}

SKADI_SUBSYSTEM_INIT_FUNCTIONS(dummy_subsystem_encrypt_init);

static struct skadi_benchmark_state benchmark_durations_half[CONFIG_BENCHMARK_DURATIONS];
EXPORT_SYMBOL(benchmark_durations_half);

static size_t benchmark_iterator;

timing_t benchmark_tstart;
EXPORT_SYMBOL(benchmark_tstart);

/* disable IRQs to prevent any influence to the measurement */
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, dummy_subsystem_benchmark)
{
   timing_t current_time = timing_counter_get();
   skadi_benchmark_add_sample(&benchmark_durations_half[benchmark_iterator++], timing_cycles_to_ns(timing_cycles_get(&benchmark_tstart, &current_time)));
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(dummy_subsystem_benchmark)
