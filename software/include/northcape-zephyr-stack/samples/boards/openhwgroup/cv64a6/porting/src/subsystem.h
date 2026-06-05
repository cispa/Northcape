#ifndef _SUBSYSTEM_H
#define _SUBSYSTEM_H

/*
 * Typical Skadi subsystem header.
 * Defines caller trampolines.
 */

#include <zephyr/skadi/skadi_subsystem.h>

struct dummy_subsystem_parameter {
    int foo;
    int bar;
};

/*
 * Subsystem call declaration.
 * Will create a caller trampoline for a subsystem call with the provided name and signature.
 * This can be called as a regular C function.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __subsystem_call, int scalar, const struct dummy_subsystem_parameter *param);

/*
 * Skadi convention: subsystem calls have wrappers that are inline functions.
 * Wrappers can be used to, e.g., derive capabilities for function pointer arguments.
 */
static inline int subsystem_call(int scalar, const struct dummy_subsystem_parameter *param){
    int ret;
    /*
     * Cannot (generally) pass a capability token that *we* have access to to the subsystem. Might be, e.g., in our private data segment!
     * Solution: *derive* a capability for the data we want to pass and drop it when we are done
     * Convenience function creates a capability with the offset corresponding to the parameter, the size of the structure and read-only permissions.
     */
    const struct dummy_subsystem_parameter *derived_param = skadi_cap_ops_derive_arg_ro(param, sizeof(*param));

    if(!derived_param){
        /*
         * The CMT is full.
         * This usually means there is a *leak* of capabilities somewhere.
         */
        return -ENOMEM;
    }
    /*
     * Caller trampoline can be called like a normal C function.
     * Scalar/by-value parameters can be passed as-is, for pointers, we need to pass a capability.
     */
    ret = __subsystem_call(scalar, derived_param);
    /* 
     * temporal safety - drop token
     */
    (void)skadi_cap_ops_drop(derived_param);

    return ret;
}

#endif
