#ifndef SKADI_OPS_DRIVER_MMIO_H
#define SKADI_OPS_DRIVER_MMIO_H

#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>

/* forward declaration to fix dependency conflict */
static inline void skadi_irq_enable(unsigned int irq, unsigned int priority);
static inline void skadi_irq_disable(unsigned int irq);
static inline int skadi_irq_is_enabled(unsigned int irq);

#include <zephyr/logging/log.h>

#define SKADI_OPS_DRIVER_BASE __builtin_assume_aligned((void*)DT_REG_ADDR(DT_COMPAT_GET_ANY_STATUS_OKAY(northcape_ops_module_1_0_0)), 8)
#define SKADI_OPS_DRIVER_BASE_IRQ __builtin_assume_aligned((void*)(DT_REG_ADDR(DT_COMPAT_GET_ANY_STATUS_OKAY(northcape_ops_module_irq_1_0_0))), 8)

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wshadow"

static inline skadi_cap_ops_regs_t *skadi_cap_ops_get_regset(void){
    if(skadi_is_in_isr()){
        return (skadi_cap_ops_regs_t *) SKADI_OPS_DRIVER_BASE_IRQ;
    }
    return (skadi_cap_ops_regs_t *) SKADI_OPS_DRIVER_BASE;
}


#define _skadi_ops_store_atomically(ADDR, VALUE) __asm__ volatile(   \
    "sd %0, 0(%1)\n\t" ::"r"(VALUE),"r"(ADDR):"memory"            \
)
#define _skadi_ops_load_atomically(ADDR,OUTPUT) __asm__ volatile(   \
    "ld %0, 0(%1)\n\t" : "=&r"(OUTPUT):"r"(ADDR):"memory"           \
)

static void skadi_ops_store_atomically(volatile uint64_t *addr, uint64_t value){
    _skadi_ops_store_atomically(addr, value);
}

static inline uint64_t skadi_ops_load_atomically(const volatile uint64_t *addr){
    uint64_t ret;
    _skadi_ops_load_atomically(addr, ret);
    return ret;
}

static inline unsigned int skadi_cap_ops_interrupt_lock(void){
    int was_enabled = skadi_irq_is_enabled(IRQ_M_TIMER);
    if(was_enabled){
        skadi_irq_disable(IRQ_M_TIMER);
    }
    return was_enabled;
}

static inline void skadi_cap_ops_interrupt_unlock(unsigned int was_enabled){
    if(was_enabled){
        skadi_irq_enable(IRQ_M_TIMER, 0);
    }
}

static bool skadi_cap_ops_inspect_generic(const void *input_token_ptr, skadi_inspect_metadata_t *metadata_out, volatile skadi_cap_ops_regs_t *cap_ops_regs){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    unsigned int timeout, irq_key;
    uint64_t input_val, current_ctrl_status;
    uint64_t new_ctrl_status;
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    timeout = 0;

    LOG_DBG("Running capability inspect with input token %"PRIx64"\n", input_token);

    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n",skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
    }

    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token);

    // no additional inputs
    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_INSPECT;

    SKADI_MB();

    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);


    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        
        skadi_cap_ops_interrupt_unlock(irq_key);
        // this is not necessarily an error condition...
        LOG_DBG("Error indicated for inspect! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    input_val = cap_ops_regs -> restriction_reg;
    
    metadata_out->restriction_body.device_specific_restriction = input_val;
    metadata_out->restriction_body.task_restriction.restriction_task_id = (uint32_t) (input_val & 0xffffffff);
    metadata_out->restriction_body.task_restriction.restriction_device_id = (uint16_t) ((input_val >> 32) & 0xffff);

    input_val = cap_ops_regs -> control_status_reg;

    input_val = input_val >> 4;

    metadata_out-> irq_accessible_permission = input_val & 0x1;

    input_val = input_val >> 1;

    metadata_out -> lockable_permission = input_val & 0x1;

    input_val = input_val >> 1;

    metadata_out -> execute_permission = input_val & 0x1;

    input_val = input_val >> 1;

    metadata_out -> write_permission = input_val & 0x1;

    input_val = input_val >> 1;

    metadata_out -> read_permission = input_val & 0x1;

    // read + 1 reserved
    input_val = input_val >> 2;

    metadata_out -> capability_length = (uint32_t)(input_val & 0xffffffff);

    input_val = input_val >> 32;

    // 3 reserved bits
    input_val = input_val >> 3;

    metadata_out -> restriction_type = (skadi_restriction_type_t) input_val & 0x3;

    input_val = cap_ops_regs -> aux1_reg;

    metadata_out -> capability_base = (uint32_t) (input_val & 0xffffffff);

    metadata_out -> refcount = (uint16_t) ((input_val >> 32) & 0xffff);

    // need to force a read to the output to acknowledge end-of-operation in the ops module
    (void)skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Inspect OK!\n");

    return 1;
}

static inline bool skadi_cap_ops_inspect(const void *input_token_ptr, skadi_inspect_metadata_t *metadata_out){
    return skadi_cap_ops_inspect_generic(input_token_ptr, metadata_out, skadi_cap_ops_get_regset());
}

static inline bool skadi_subsystem_can_accept_function_pointer(uint64_t input_token, const char **reason, uint32_t my_task_id, bool is_irq, bool accept_own_task_id){
    unsigned int timeout, irq_key;
    uint64_t input_val, current_ctrl_status;
    uint64_t new_ctrl_status;
    bool return_ok = false;
    skadi_restriction_type_t restriction_type;
    uint32_t restriction_task_id;
    bool execute_permission;
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    timeout = 0;

    LOG_DBG("Running capability inspect with input token %"PRIx64"\n", input_token);

    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n",skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
        return_ok = false;
        goto out;
    }

    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token);

    // no additional inputs
    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_INSPECT;

    SKADI_MB();

    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);

    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        goto out;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        
        skadi_cap_ops_interrupt_unlock(irq_key);
        // this is not necessarily an error condition...
        LOG_DBG("Error indicated for inspect! Current control status register %"PRIx64"!\n", current_ctrl_status);
        goto out;
    }

    input_val = cap_ops_regs -> restriction_reg;
    
    restriction_task_id = (uint32_t) (input_val & 0xffffffff);
    input_val = cap_ops_regs -> control_status_reg;

    input_val = cap_ops_regs -> control_status_reg;

    input_val = input_val >> 4;

    input_val = input_val >> 1;

    input_val = input_val >> 1;

    input_val = input_val >> 1;

    input_val = input_val >> 1;

    input_val = input_val >> 2;

    input_val = input_val >> 32;

    input_val = input_val >> 3;

    restriction_type = (skadi_restriction_type_t) input_val & 0x3;

    execute_permission = input_val & 0x1;

    // need to force a read to the output to acknowledge end-of-operation in the ops module
    (void)skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Inspect OK!\n");
    return_ok = true;
out:
    if(!return_ok){
        if(reason){
            *reason = "Could not inspect function pointer!";
        }
        return false;
    }
    if(restriction_type != SKADI_RESTRICTIONS_SET_TASK_ID){
        if(reason){
            *reason = "Function pointer does not have SET_TASK_ID restriction!";
        }
        return false; /* caller could hijack our task ID */
    }
    if(restriction_task_id == my_task_id){
        if(reason){
            *reason = "Function pointer has our task ID!";
        }
        return accept_own_task_id; /* jump from one subsystem into the other, which is probably not what we want, with a few exceptions where a different kind of wrapper is used */
    }

    return true; /* good to call */
}


static inline bool skadi_cap_ops_create(const void *input_token_ptr, skadi_restriction_t restriction,
                                            const bool direction, const uint32_t new_segment_length, skadi_permission_type_t permissions, void **output){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    const skadi_capability_type_t capability_type = skadi_allocator_appropriate_capability_type_for_size(new_segment_length);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    timeout = 0;

    LOG_DBG("Running capability creation with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d creation direction %d new segment length %"PRIu32" read permission %d write permission %d execute permission %d lockable permission %d IRQ accessible %d cacheable TLB %d cacheable acces %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, direction, new_segment_length, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE, permissions & SKADI_PERMISSION_LOCKABLE, permissions & SKADI_PERMISSION_IRQ_ACCESSIBLE, permissions & SKADI_PERMISSION_CACHEABLE_TLB, permissions & SKADI_PERMISSION_CACHEABLE_ACCESS);

    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n",skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
    }

    // relative order of input token and restriction does not matter
    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token);
    
    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        skadi_ops_store_atomically(&cap_ops_regs->restriction_reg, new_restriction);
    }

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_CREATE;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_TLB ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_ACCESS ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_IRQ_ACCESSIBLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_LOCKABLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_LOCKABLE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_EXECUTE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_WRITE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_READ ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS;


    new_ctrl_status = new_ctrl_status | (restriction.restriction_type != SKADI_RESTRICTIONS_NONE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) new_segment_length) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_NEW_SEGMENT_LENGTH_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (direction ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_DIRECTION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) capability_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) restriction.restriction_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS;

    LOG_DBG("New restriction comes to %"PRIx64" new control to %"PRIx64"\n",new_restriction, new_ctrl_status);

    SKADI_MB();
    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);
    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n",current_ctrl_status);
        return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n",current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for create! Current control status register %"PRIx64"!\n",current_ctrl_status);
        return 0;
    }

    *output = (void *) skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Create OK! Output token %p!\n",*output);

    return 1;
}


static bool skadi_cap_ops_derive_unlocked(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t new_segment_length, const uint32_t parent_offset,
                                                    skadi_permission_type_t permissions, skadi_capability_type_t min_capability_type, void **output){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout;
    skadi_capability_type_t capability_type = skadi_allocator_appropriate_capability_type_for_size(new_segment_length);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    capability_type = skadi_pick_larger_capability_type(capability_type, min_capability_type);

    timeout = 0;
    
    __ASSERT_NO_MSG(new_segment_length);

    LOG_DBG("Running capability derivation with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d new segment length %"PRIu32" parent offset %"PRIu32" read permission %d write permission %d execute permission %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, new_segment_length, parent_offset, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n",skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
    }

    // relative order of input token and restriction does not matter
    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token);

    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        skadi_ops_store_atomically(&cap_ops_regs->restriction_reg, new_restriction);
    }
    if(parent_offset){
        // default 0
        // lower 32 bit are parent offset
        // upper 32 bit are currently reserved
        skadi_ops_store_atomically(&cap_ops_regs->aux1_reg, parent_offset);
    }

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_DERIVE;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_TLB ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_ACCESS ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_IRQ_ACCESSIBLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS;
    /* lock is not valid */
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_EXECUTE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_WRITE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_READ ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS;


    new_ctrl_status = new_ctrl_status | (restriction.restriction_type != SKADI_RESTRICTIONS_NONE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) new_segment_length) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_NEW_SEGMENT_LENGTH_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t)capability_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) restriction.restriction_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS;

    LOG_DBG("New restriction comes to %"PRIx64" new control to %"PRIx64"\n",new_restriction, new_ctrl_status);

    SKADI_MB();
    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);
    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        LOG_ERR("Error indicated for derive! Current control status register %"PRIx64" for capability derivation with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d new segment length %"PRIu32" parent offset %"PRIu32" read permission %d write permission %d execute permission %d!\n", current_ctrl_status,  input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, new_segment_length, parent_offset, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);
        return 0;
    }

    *output = (void *) skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    LOG_DBG("Derive OK! Output token %p!\n",*output);

    return 1;
}

static inline bool skadi_cap_ops_derive(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t new_segment_length, const uint32_t parent_offset,
    skadi_permission_type_t permissions, void **output){
    bool ret;
    unsigned int irq_key = skadi_cap_ops_interrupt_lock();

    ret = skadi_cap_ops_derive_unlocked(input_token_ptr, restriction, new_segment_length, parent_offset, permissions, SKADI_CAPABILITY_TYPE_OFFSET_8_BIT, output);

    skadi_cap_ops_interrupt_unlock(irq_key);

    return ret;

}

static inline bool skadi_cap_ops_derive_min_cap_type(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t new_segment_length, const uint32_t parent_offset,
    skadi_permission_type_t permissions, skadi_capability_type_t min_type, void **output){
    bool ret;
    unsigned int irq_key = skadi_cap_ops_interrupt_lock();

    ret = skadi_cap_ops_derive_unlocked(input_token_ptr, restriction, new_segment_length, parent_offset, permissions, min_type, output);

    skadi_cap_ops_interrupt_unlock(irq_key);

    return ret;

}

static inline void *__skadi_cap_ops_derive_arg(const void* input, const uint32_t length, const char *file, int line){
        void *output = 0;
        skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
        bool ret;
        
        __ASSERT_NO_MSG(length);
        
        ret = skadi_cap_ops_derive(input, restriction, length, skadi_get_capability_offset(input), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &output);
        
        __ASSERT(input, "Did not expect to derive from null pointer - %s:%u!", file, line);

        __ASSERT(ret, "Expected derive to succeed - %s:%u!", file, line);
        __ASSERT_NO_MSG(output);

        return (void *)output;
    }

static inline void *__skadi_cap_ops_derive_arg_allperm(const void* input, const uint32_t length, const char *file, int line){
        void *output = 0;
        skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
        bool ret;
        
        __ASSERT_NO_MSG(length);
        
        ret = skadi_cap_ops_derive(input, restriction, length, skadi_get_capability_offset(input), SKADI_ALL_PERMISSIONS, &output);
        
        __ASSERT(input, "Did not expect to derive from null pointer - %s:%u!", file, line);

        __ASSERT(ret, "Expected derive to succeed - %s:%u!", file, line);
        __ASSERT_NO_MSG(output);

        return (void *)output;
    }


/* simplified versions of derive for passing known-size arguments, e.g., from data segment, through subsystem calls */
static inline void *__skadi_cap_ops_derive_arg_tid(const void* input, const uint32_t length, skadi_task_id_t task_id, const char *file, int line){
    void *output = 0;
    skadi_restriction_t restriction = SKADI_TASK_ID_BOUND_RESTRICTION(task_id, SKADI_DEVICE_ID_CPU);
    bool ret;
    
    __ASSERT_NO_MSG(length);
    
    ret = skadi_cap_ops_derive(input, restriction, length, skadi_get_capability_offset(input), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &output);
    
    __ASSERT(input, "Did not expect to derive from null pointer - %s:%d!", file, line);

    __ASSERT(ret, "Expected derive to succeed - %s:%d!", file, line);
    __ASSERT_NO_MSG(output);

    return (void *)output;
}

static inline const void *__skadi_cap_ops_derive_arg_ro(const void* input, const uint32_t length, const char *file, int line){
    void *output = 0;
    skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
    bool ret;
    
    __ASSERT_NO_MSG(length);

    ret = skadi_cap_ops_derive(input, restriction, length, skadi_get_capability_offset(input), SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &output);

    __ASSERT(input, "Did not expect to derive from null pointer - %s:%d!", file, line);

    __ASSERT(ret, "Expected derive to succeed - %s:%d!", file, line);
    __ASSERT_NO_MSG(output);
    

    return (const void *)output;
}

static inline void *__skadi_cap_ops_derive_arg_wo(void* input, const uint32_t length, const char *file, int line){
    void *output = 0;
    skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
    bool ret;
    
    __ASSERT(length, "Expected length to be non-zero - %s:%d!", file, line);
    __ASSERT(input, "Did not expect to derive from null pointer - %s:%d!", file, line);
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmaybe-uninitialized"
    ret = skadi_cap_ops_derive(input, restriction, length, skadi_get_capability_offset(input), SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, &output);
#pragma GCC diagnostic pop
    __ASSERT(ret, "Expected derive to succeed - %s:%d!", file, line);
    __ASSERT_NO_MSG(output);

    return (void *)output;
}

static inline bool skadi_cap_ops_drop(const void *input_token_ptr){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    uint64_t new_ctrl_status, current_ctrl_status;
    unsigned int timeout;
    int irq_key;
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    timeout = 0;

    LOG_DBG("Running capability drop with input token %"PRIx64"!\n", input_token);

    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        /* TODO gcc does not like this line for some reason */
        /* LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n", skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)); */
    
    }

    // relative order of input token and restriction does not matter
    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token);

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_DROP;

    LOG_DBG("New control is %"PRIx64"\n", new_ctrl_status);

    SKADI_MB();

    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);

    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");
    
    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        /* TODO gcc does not like this line for some reason */
        /* LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n",current_ctrl_status); */
        skadi_cap_ops_interrupt_unlock(irq_key);
        return 0;
    }
    
    // need to force a read to the output to acknowledge end-of-operation in the ops module
    (void)skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Drop OK!");

    return 1;
}

static inline bool skadi_cap_ops_merge_noinspect(const void *input_token_left_ptr, const void *input_token_right_ptr, skadi_restriction_t restriction,
    skadi_permission_type_t permissions, skadi_capability_type_t capability_type, void **output){
    const uint64_t input_token_left = (uint64_t) input_token_left_ptr, input_token_right = (uint64_t) input_token_right_ptr;
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    timeout = 0;

    LOG_DBG("Running capability merge with input token %"PRIx64" and %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d read permission %d write permission %d execute permission %d lockable permission %d irq accessible permission %d cacheable TLB permission %d cacheable access permission %d!\n", input_token_left, input_token_right, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE, permissions & SKADI_PERMISSION_LOCKABLE, permissions & SKADI_PERMISSION_IRQ_ACCESSIBLE, permissions & SKADI_PERMISSION_CACHEABLE_TLB, permissions & SKADI_PERMISSION_CACHEABLE_ACCESS);

    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
    LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n", skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
    }

    // relative order of input token and restriction does not matter
    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token_left);

    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        skadi_ops_store_atomically(&cap_ops_regs->restriction_reg, new_restriction);
    }

    skadi_ops_store_atomically(&cap_ops_regs->aux1_reg, input_token_right);

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_MERGE;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_TLB ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_ACCESS ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_IRQ_ACCESSIBLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_LOCKABLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_LOCKABLE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_EXECUTE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_WRITE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_READ ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS;


    new_ctrl_status = new_ctrl_status | (restriction.restriction_type != SKADI_RESTRICTIONS_NONE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t)capability_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) restriction.restriction_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS;

    LOG_DBG("New restriction comes to %"PRIx64" new control to %"PRIx64"\n",new_restriction, new_ctrl_status);

    SKADI_MB();
    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);
    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
    timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
    return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_ERR("Error indicated for merge! Current control status register %"PRIx64"!\n", current_ctrl_status);
    return 0;
    }

    *output =  (void*) skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Merge OK! Output token %p!\n",*output);

    return 1;
}

static inline bool skadi_cap_ops_merge(const void *input_token_left_ptr, const void *input_token_right_ptr, skadi_restriction_t restriction,
                                            skadi_permission_type_t permissions, void **output){
    skadi_inspect_metadata_t left_metadata, right_metadata;
    skadi_capability_type_t capability_type;
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    if(skadi_cap_ops_inspect(input_token_left_ptr, &left_metadata) == false || skadi_cap_ops_inspect(input_token_right_ptr, &right_metadata) == false){
        LOG_ERR("Could not inspect inputs!");
        return false;
    }

    __ASSERT((uintptr_t)left_metadata.capability_base + (uintptr_t) left_metadata.capability_length == (uintptr_t) right_metadata.capability_base, "Expected left capability with start %"PRIu32" size %"PRIu32" to be adjacent with right capabiltiy start %"PRIu32" length %"PRIu32"!", left_metadata.capability_base, left_metadata.capability_length, right_metadata.capability_base, right_metadata.capability_length);

    capability_type = skadi_allocator_appropriate_capability_type_for_size(left_metadata.capability_length + right_metadata.capability_length);

    return skadi_cap_ops_merge_noinspect(input_token_left_ptr, input_token_right_ptr, restriction, permissions, capability_type, output);
}

static inline bool skadi_cap_ops_clone(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    skadi_capability_type_t capability_type = skadi_get_capability_type(input_token_ptr);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    timeout = 0;

    LOG_DBG("Running capability clone with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d read permission %d write permission %d execute permission %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n", skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
    }

    // relative order of input token and restriction does not matter
    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token);

    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        skadi_ops_store_atomically(&cap_ops_regs->restriction_reg, new_restriction);
    }

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_CLONE;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_TLB ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_ACCESS ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_IRQ_ACCESSIBLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS;
    /* lock is not valid */
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_EXECUTE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_WRITE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_READ ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS;


    new_ctrl_status = new_ctrl_status | (restriction.restriction_type != SKADI_RESTRICTIONS_NONE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t)capability_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) restriction.restriction_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS;

    LOG_DBG("New restriction comes to %"PRIx64" new control to %"PRIx64"\n",new_restriction, new_ctrl_status);

    SKADI_MB();
    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);
    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for clone! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    *output =  (void*) skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Clone OK! Output token %p!\n",*output);

    return 1;
}


static inline bool __skadi_cap_ops_revoke(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output, int opcode){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int irq_key;
    skadi_capability_type_t capability_type = skadi_get_capability_type(input_token_ptr);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    LOG_DBG("Running capability revocation with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d read permission %d write permission %d execute permission %d lockable permission %d irq accessible %d cacheable TLB permission %d cacheable access permission %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE, permissions & SKADI_PERMISSION_LOCKABLE, permissions & SKADI_PERMISSION_IRQ_ACCESSIBLE, permissions & SKADI_PERMISSION_CACHEABLE_TLB, permissions & SKADI_PERMISSION_CACHEABLE_ACCESS);
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n", skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
    }

    // relative order of input token and restriction does not matter
    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token);

    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        skadi_ops_store_atomically(&cap_ops_regs->restriction_reg, new_restriction);
    }

    new_ctrl_status = opcode;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_TLB ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_ACCESS ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_IRQ_ACCESSIBLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_LOCKABLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_LOCKABLE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_EXECUTE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_WRITE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_READ ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS;


    new_ctrl_status = new_ctrl_status | (restriction.restriction_type != SKADI_RESTRICTIONS_NONE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t)capability_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) restriction.restriction_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS;

    LOG_DBG("New restriction comes to %"PRIx64" new control to %"PRIx64"\n",new_restriction, new_ctrl_status);

    SKADI_MB();
    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);
    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    /* no timeout - can take a while for large capabilities */
    while(((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0);

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for revoke! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    *output = (void*) skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Revoke OK! Output token %p!\n",*output);

    return 1;
}

static inline bool skadi_cap_ops_revoke(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output){
    return __skadi_cap_ops_revoke(input_token_ptr, restriction, permissions, output, SKADI_CAPABILITY_OPS_OPERATION_REVOKE);
}


static inline bool skadi_cap_ops_lock(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    skadi_capability_type_t capability_type = skadi_get_capability_type(input_token_ptr);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    timeout = 0;

    // sanity check for Skadi OS
    if(input_token < 0xffff){
        LOG_ERR("Refusing to lock root cap!");
        return false;
    }

    LOG_DBG("Running capability locking with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d read permission %d write permission %d execute permission %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n", skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
    }

    // relative order of input token and restriction does not matter
    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token);

    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        skadi_ops_store_atomically(&cap_ops_regs->restriction_reg, new_restriction);
    }

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_LOCK;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_TLB ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_ACCESS ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_IRQ_ACCESSIBLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS;
    /* lock is not valid */
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_EXECUTE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_WRITE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_READ ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS;


    new_ctrl_status = new_ctrl_status | (restriction.restriction_type != SKADI_RESTRICTIONS_NONE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t)capability_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) restriction.restriction_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS;

    LOG_DBG("New restriction comes to %"PRIx64" new control to %"PRIx64"\n",new_restriction, new_ctrl_status);

    SKADI_MB();
    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);
    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for lock! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    *output = (void*) skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Lock OK! Output token %p!\n",*output);

    return 1;
}

static inline bool skadi_cap_ops_restrict(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t segment_length_subtrahend, const uint32_t offset_addend, skadi_permission_type_t permissions){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    timeout = 0;

    LOG_DBG("Running capability restrict with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d segment length subtrahend %"PRIu32" offset addend %"PRIu32" read permission %d write permission %d execute permission %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, segment_length_subtrahend, offset_addend, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n", skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
    }

    // relative order of input token and restriction does not matter
    skadi_ops_store_atomically(&cap_ops_regs->input_token_reg, input_token);

    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        skadi_ops_store_atomically(&cap_ops_regs->restriction_reg, new_restriction);
    }

    if(offset_addend){
        // default 0
        // lower 32 bit are offset addend
        // upper 32 bit are currently reserved
        skadi_ops_store_atomically(&cap_ops_regs->aux1_reg, offset_addend);
    }
    
    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_RESTRICT;

    // lockable, cow only applied to base direct capability, ignored for indirect
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_TLB ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_ACCESS ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_IRQ_ACCESSIBLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_LOCKABLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_LOCKABLE_PERMISSION_SHIFT_BITS;
    
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_EXECUTE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_WRITE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_READ ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS;
    


    new_ctrl_status = new_ctrl_status | (restriction.restriction_type != SKADI_RESTRICTIONS_NONE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) segment_length_subtrahend) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_NEW_SEGMENT_LENGTH_SHIFT_BITS;
    
    new_ctrl_status = new_ctrl_status | ((uint64_t) restriction.restriction_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS;

    LOG_DBG("New restriction comes to %"PRIx64" new control to %"PRIx64"\n",new_restriction, new_ctrl_status);

    SKADI_MB();
    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);
    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n", skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for restrict! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }
    
    // need to force a read to the output to acknowledge end-of-operation in the ops module
    (void) skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Restrict OK!");

    return 1;
}


static inline bool skadi_cap_ops_sweep(void){
    volatile skadi_cap_ops_regs_t *cap_ops_regs = skadi_cap_ops_get_regset();
    uint64_t  new_ctrl_status, current_ctrl_status;
    unsigned int irq_key;
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);


    LOG_DBG("Running capability sweep!");
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((skadi_ops_load_atomically(&cap_ops_regs->control_status_reg) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        LOG_ERR("Error - last operation stuck! Current control status register %"PRIx64"!\n", skadi_ops_load_atomically(&cap_ops_regs->control_status_reg));
    }

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_SWEEP;

    skadi_ops_store_atomically(&cap_ops_regs->control_status_reg, new_ctrl_status);
    SKADI_MB();

    LOG_DBG("Waiting for capability operations to be done!\n");

    /* no timeout - can take a while for large capabilities */
    while(((current_ctrl_status = skadi_ops_load_atomically(&cap_ops_regs->control_status_reg)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0);

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for sweep! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    (void)skadi_ops_load_atomically(&cap_ops_regs->output_reg);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Sweep OK!");

    return 1;
}

static inline uint64_t skadi_cap_ops_get_capability_count(void){
    const skadi_cap_ops_regs_t *skadi_regs = skadi_cap_ops_get_regset();

    return skadi_regs->capability_count & SKADI_CAP_OPS_COUNT_COUNT_MASK;
}

static inline bool skadi_cap_ops_get_northcape_enabled(void){
    const skadi_cap_ops_regs_t *skadi_regs = skadi_cap_ops_get_regset();

    return skadi_regs->capability_count & SKADI_CAP_OPS_COUNT_NORTHCAPE_ENABLE_STATUS_MASK;
}

/* can only be enabled once with no way to go back */
static inline void skadi_cap_ops_set_northcape_enabled(void){
    skadi_cap_ops_regs_t *skadi_regs = skadi_cap_ops_get_regset();


    skadi_ops_store_atomically(&skadi_regs->capability_count, SKADI_CAP_OPS_COUNT_NORTHCAPE_ENABLE_STATUS_MASK);
    SKADI_MB();
    /* need to spin the enable flag so we do not return before completion */
    while(!skadi_cap_ops_get_northcape_enabled());
    /* setup performance counters */
    SKADI_PERF_COUNTER_CONFIGURE_L1_INSTR_MISS();
    SKADI_PERF_COUNTER_CONFIGURE_L1_DATA_MISS();
    SKADI_PERF_COUNTER_CONFIGURE_L2_RESOLVER_MISS();
    SKADI_PERF_COUNTER_CONFIGURE_L2_OPS_MISS();
    SKADI_PERF_COUNTER_CONFIGURE_EXTRA_ICACHE_DELAY();
    SKADI_PERF_COUNTER_CONFIGURE_MISSUNIT_STALL();
    SKADI_PERF_COUNTER_CONFIGURE_L2_FULL_WIPE();
}

static inline uint64_t skadi_cap_ops_get_trng_bits(void){
    const skadi_cap_ops_regs_t *skadi_regs = skadi_cap_ops_get_regset();
    uint64_t ret;

    do {
        /* the hardware ensures that each 64-bit sequence is only returned in a single 64-bit read; read value is 0 when no RNG bits available*/
        ret = skadi_regs->trng;
    } while(!ret);
    
    return ret;
}
#pragma GCC diagnostic pop

#ifndef SKADI_SUBSYSTEM_H
/* dependency conflict */
#include <zephyr/skadi/skadi_irq.h>
#endif

#endif /* SKADI_OPS_DRIVER_MMIO_H */
