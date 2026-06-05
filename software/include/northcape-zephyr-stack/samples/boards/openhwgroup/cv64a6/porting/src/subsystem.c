/**
 * @file Provides a subsystem that can be used to compute a one-time pad encryption of a uint64_t.
 */
#include <stdio.h>

#include <zephyr/skadi/skadi_subsystem.h>

#include "subsystem.h"

static bool initialized = false;

/*
 * Actual implementation of subsystem call.
 * Convention: Logic is contained in a normal C function, which can be called through subsystem call or from the subsystem. 
 */
int subsystem_call_impl(int scalar, const struct dummy_subsystem_parameter *param){
    printf("Hello world from the subsystem (Task ID %d) was initialized: %d\n", SKADI_CURRENT_TASK_ID, initialized);
    /*
     * arguments work as they should
     */
    printf("Scalar parameter was: %d\ncapability-conveyed struct was {foo: %d, bar: %d}\n",scalar, param->foo, param->bar);

    return 0;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __subsystem_call, int scalar, const struct dummy_subsystem_parameter *param)
    return subsystem_call_impl(scalar, param);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__subsystem_call)

/*
 * Called immediately when the subsystem is loaded. 
 */
static bool dummy_init_function(void){
    printf("This text will be printed via the early console in the loader!\n");

    initialized = true;

    return true;
}
SKADI_SUBSYSTEM_INIT_FUNCTIONS(dummy_init_function);
