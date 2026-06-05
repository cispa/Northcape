#ifndef SKADI_OPS_DRIVER_CSR_H
#define SKADI_OPS_DRIVER_CSR_H

#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
#include <zephyr/sys/byteorder.h>

/* forward declaration to fix dependency conflict */
static inline void skadi_irq_enable(unsigned int irq, unsigned int priority);
static inline void skadi_irq_disable(unsigned int irq);
static inline int skadi_irq_is_enabled(unsigned int irq);

#include <zephyr/logging/log.h>

#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS

#define DECLARE_INIT_CYCLES_COUNT(OPERATION)        \
    const long OPERATION##_start = csr_read(mcycle);\
    long OPERATION##_end;                           \
    unsigned long OPERATION##_stats

#define READ_STATS_CSR(OPERATION)                                                               \
    OPERATION##_stats = csr_read(SKADI_CAP_OPS_CSR_STATS)

#define UPDATE_CYCLES_COUNT(OPERATION)                                                          \
    OPERATION##_end = csr_read(mcycle);                                                         \
    atomic_add(&skadi_cycles_##OPERATION, OPERATION##_end - OPERATION##_start);                 \
    atomic_add(&skadi_cycles_##OPERATION##_ops, OPERATION##_stats >> 32);                       \
    atomic_add(&skadi_failed_occupied_checks_##OPERATION##_ops, OPERATION##_stats & 0xffffffff)

#if defined(SKADI_SUBSYSTEM)

#else

/* loader is given static versions of these variables - not shared with OS */
extern atomic_t skadi_cycles_create;
extern atomic_t skadi_cycles_derive;
extern atomic_t skadi_cycles_drop;
extern atomic_t skadi_cycles_merge;
extern atomic_t skadi_cycles_clone;
extern atomic_t skadi_cycles_revoke;
extern atomic_t skadi_cycles_lock;
extern atomic_t skadi_cycles_inspect;
extern atomic_t skadi_cycles_restrict;
extern atomic_t skadi_cycles_sweep;

extern atomic_t skadi_cycles_create_ops;
extern atomic_t skadi_cycles_derive_ops;
extern atomic_t skadi_cycles_drop_ops;
extern atomic_t skadi_cycles_merge_ops;
extern atomic_t skadi_cycles_clone_ops;
extern atomic_t skadi_cycles_revoke_ops;
extern atomic_t skadi_cycles_lock_ops;
extern atomic_t skadi_cycles_inspect_ops;
extern atomic_t skadi_cycles_restrict_ops;
extern atomic_t skadi_cycles_sweep_ops;

extern atomic_t skadi_failed_occupied_checks_create_ops;
extern atomic_t skadi_failed_occupied_checks_derive_ops;
extern atomic_t skadi_failed_occupied_checks_drop_ops;
extern atomic_t skadi_failed_occupied_checks_merge_ops;
extern atomic_t skadi_failed_occupied_checks_clone_ops;
extern atomic_t skadi_failed_occupied_checks_revoke_ops;
extern atomic_t skadi_failed_occupied_checks_lock_ops;
extern atomic_t skadi_failed_occupied_checks_inspect_ops;
extern atomic_t skadi_failed_occupied_checks_restrict_ops;
extern atomic_t skadi_failed_occupied_checks_sweep_ops;


#endif /* SKADI_SUBSYSTEM */

#else

#define DECLARE_INIT_CYCLES_COUNT(OPERATION)
#define READ_STATS_CSR(OPERATION)
#define UPDATE_CYCLES_COUNT(OPERATION)

#endif /* CONFIG_SKADI_TRACK_CYCLES_OPS */

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wshadow"

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

static inline bool skadi_cap_ops_inspect_generic(const void *input_token_ptr, skadi_inspect_metadata_t *metadata_out){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    unsigned int timeout, irq_key;
    uint64_t input_val, current_ctrl_status;
    uint64_t new_ctrl_status;
    DECLARE_INIT_CYCLES_COUNT(inspect);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    timeout = 0;

    LOG_DBG("Running capability inspect with input token %"PRIx64"\n", input_token);

    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - last operation stuck! Current control status register %lx!\n",csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
    }

    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token);

    // no additional inputs
    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_INSPECT;

    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        
        __asm__ volatile("ebreak");

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


    READ_STATS_CSR(inspect);

    input_val = csr_read(SKADI_CAP_OPS_CSR_RESTRICTION);
    
    metadata_out->restriction_body.device_specific_restriction = input_val;
    metadata_out->restriction_body.task_restriction.restriction_task_id = (uint32_t) (input_val & 0xffffffff);
    metadata_out->restriction_body.task_restriction.restriction_device_id = (uint16_t) ((input_val >> 32) & 0xffff);

    input_val = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS);

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

    input_val = csr_read(SKADI_CAP_OPS_CSR_AUX1);

    metadata_out -> capability_base = (uint32_t) (input_val & 0xffffffff);

    metadata_out -> refcount = (uint16_t) ((input_val >> 32) & 0xffff);

    // need to force a read to the output to acknowledge end-of-operation in the ops module
    (void)csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Inspect OK!\n");

    UPDATE_CYCLES_COUNT(inspect);

    return 1;
}

static inline bool skadi_cap_ops_inspect(const void *input_token_ptr, skadi_inspect_metadata_t *metadata_out){
    return skadi_cap_ops_inspect_generic(input_token_ptr, metadata_out);
}

static inline bool skadi_subsystem_can_accept_function_pointer(uint64_t input_token, const char **reason, uint32_t my_task_id, bool is_irq, bool accept_own_task_id){
    unsigned int timeout, irq_key;
    uint64_t input_val, current_ctrl_status;
    uint64_t new_ctrl_status;
    bool return_ok = false;
    skadi_restriction_type_t restriction_type;
    uint32_t restriction_task_id;
    bool execute_permission;
    DECLARE_INIT_CYCLES_COUNT(inspect);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    timeout = 0;

    LOG_DBG("Running capability inspect with input token %"PRIx64"\n", input_token);

    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - last operation stuck! Current control status register %lx!\n",csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
        return_ok = false;
        goto out;
    }

    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token);

    // no additional inputs
    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_INSPECT;

    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        __asm__ volatile("ebreak");
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

    READ_STATS_CSR(inspect);

    input_val = csr_read(SKADI_CAP_OPS_CSR_RESTRICTION);
    
    restriction_task_id = (uint32_t) (input_val & 0xffffffff);

    input_val = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS);

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
    (void)csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Inspect OK!\n");

    UPDATE_CYCLES_COUNT(inspect);

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

#if defined(CONFIG_SKADI_DEBUG)
static inline bool __skadi_cap_ops_create(const void *input_token_ptr, skadi_restriction_t *restriction,
                                            const bool direction, const uint32_t new_segment_length, skadi_permission_type_t permissions, const skadi_capability_type_t capability_type, void **output){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    DECLARE_INIT_CYCLES_COUNT(create);
    
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    timeout = 0;

    LOG_DBG("Running capability creation with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d creation direction %d new segment length %"PRIu32" read permission %d write permission %d execute permission %d lockable permission %d IRQ accessible %d cacheable TLB %d cacheable acces %d!\n", input_token, restriction->restriction_body.task_id_body.restriction_device, restriction->restriction_body.task_id_body.restriction_task, restriction->restriction_type != SKADI_RESTRICTIONS_NONE, direction, new_segment_length, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE, permissions & SKADI_PERMISSION_LOCKABLE, permissions & SKADI_PERMISSION_IRQ_ACCESSIBLE, permissions & SKADI_PERMISSION_CACHEABLE_TLB, permissions & SKADI_PERMISSION_CACHEABLE_ACCESS);

    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - last operation stuck! Current control status register %lx!\n",csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
    }

    // relative order of input token and restriction does not matter
    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token);
    // no restriction is default - no write necessary
    if(restriction->restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(*restriction);
        csr_write(SKADI_CAP_OPS_CSR_RESTRICTION, new_restriction);
    }

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_CREATE;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_TLB ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_ACCESS ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_IRQ_ACCESSIBLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_LOCKABLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_LOCKABLE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_EXECUTE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_WRITE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_READ ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS;


    new_ctrl_status = new_ctrl_status | (restriction->restriction_type != SKADI_RESTRICTIONS_NONE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) new_segment_length) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_NEW_SEGMENT_LENGTH_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (direction ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_DIRECTION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) capability_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) restriction->restriction_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS;

    LOG_DBG("New restriction comes to %"PRIx64" new control to %"PRIx64"\n",new_restriction, new_ctrl_status);
   
    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        __asm__ volatile("ebreak");
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n",current_ctrl_status);
        return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n",current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        __asm__ volatile("ebreak");
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for create! Current control status register %"PRIx64"!\n",current_ctrl_status);
        return 0;
    }

    READ_STATS_CSR(create);

    *output = (void *) csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Create OK! Output token %p!\n",*output);

    UPDATE_CYCLES_COUNT(create);

    return 1;
}

#else 
static bool __attribute__((naked)) __skadi_cap_ops_create(const void *input_token_ptr, skadi_restriction_t *restriction,
                                            const bool direction, const uint32_t new_segment_length, skadi_permission_type_t permissions, const skadi_capability_type_t capability_type, void **output){
#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS
    (void)skadi_failed_occupied_checks_create_ops;
    (void)skadi_cycles_create_ops;
    (void)skadi_cycles_create;
#endif
    __asm__(
            "li t0, " STRINGIFY(1<<IRQ_M_TIMER)"\n\t"
            "csrrc t0, mie, t0\n\t" /* disable and get old value, atomically */
            "csrr t1," STRINGIFY(SKADI_CAP_OPS_CSR_CTRL_STATUS)"\n\t"
            "li t2, "STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK)"\n\t"
            "and t1, t1, t2\n\t"
            "bnez t1, fail_create\n\t"
            "csrw " STRINGIFY(SKADI_CAP_OPS_CSR_INPUT) ", %0\n\t"
            "ld t5, 8(%1)\n\t" /* restriction type */
            "li t4, 0\n\t" /* restriction enable flag */
            "beqz t5, restr_set_create\n\t"
            "li t4, 1\n\t" /* restriction enable flag */
            "ld t2, 0(%1)\n\t" /* assumes that layout matches exactly */
            "csrw " STRINGIFY(SKADI_CAP_OPS_CSR_RESTRICTION) ", t2\n\t"
            "restr_set_create:\n\t"
            "li t1, " STRINGIFY(SKADI_CAPABILITY_OPS_OPERATION_CREATE) "\n\t"
            "mv t3, %3\n\t" /* modifieable copy of permissions */
            ""
            "andi t2, t3, 0x1\n\t" /* get read permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply read */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get write permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply write */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get execute permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply execute */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get lockable permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_LOCKABLE_PERMISSION_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply lockable */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get IRQ accessible permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply IRQ accessible */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get cacheable TLB permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply cacheable TLB */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get cacheable access permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply cacheable access */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "slli t4, t4," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS) "\n\t"
            "or t1, t1, t4\n\t" /* apply restriction enabled */
            ""
            "slli t2, %2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_NEW_SEGMENT_LENGTH_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply segment lenght */
            ""
            "slli t2, %5," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply capability type*/
            ""
            "slli t5, t5," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS) "\n\t"
            "or t1, t1, t5\n\t" /* apply restriction type */
            ""
            "slli t5, %6," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_DIRECTION_SHIFT_BITS) "\n\t"
            "or t1, t1, t5\n\t" /* apply direction */
            ""
            "csrw " STRINGIFY(SKADI_CAP_OPS_CSR_CTRL_STATUS) ", t1\n\t" /* start operation */
            "li t1," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) "\n\t"
            "status_check_loop_create:\n\t"
            "csrr t2, " STRINGIFY(SKADI_CAP_OPS_CSR_CTRL_STATUS) "\n\t"
            "and t3, t2, t1\n\t"
            "beqz t3, status_check_loop_create\n\t" /* still ongoing */
            "li t1," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK)"\n\t"
            "and t3, t2, t1\n\t"
            "bnez t3, fail_create\n\t"
            ::"r"(input_token_ptr),"r"(restriction),"r"(new_segment_length),"r"(permissions),"r"(output),"r"(capability_type),"r"(direction)
            :"t0","t1","t2","t3","t4","t5","t6","a0"
        );
#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS
        __asm__ (
            "csrr a0, " STRINGIFY(SKADI_CAP_OPS_CSR_STATS)"\n\t"
            "srli a0, a0, 32\n\t" /* high 32 bits */
            "ld t1, .skadi_cycles_create_ops_reloc\n\t"
            "amoadd.d zero, a0, 0(t1)\n\t"
            :::"a0","t1"
        );
#endif
        __asm__(
            "li a0, 1\n\t"
            "csrr t1, " STRINGIFY(SKADI_CAP_OPS_CSR_OUTPUT) "\n\t"
            "sd t1, 0(%4)\n\t"
            "csrs mie, t0\n\t"
            "ret\n\t"
            "fail_create:\n\t"
            "ebreak\n\t"
            ::"r"(input_token_ptr),"r"(restriction),"r"(new_segment_length),"r"(permissions),"r"(output),"r"(capability_type),"r"(direction)
            :"t0","t1","t2","t3","t4","t5","t6","a0"
        );
#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS
        __asm__(
            ".p2align 3\n\t"
            ".skadi_cycles_create_ops_reloc:\n\t"
            ".dword skadi_cycles_create_ops\n\t"
        );
#endif
}
#endif

static inline bool skadi_cap_ops_create(const void *input_token_ptr, skadi_restriction_t restriction,
                                            const bool direction, const uint32_t new_segment_length, skadi_permission_type_t permissions, void **output){
    const skadi_capability_type_t capability_type = skadi_allocator_appropriate_capability_type_for_size(new_segment_length);
    bool ret;


    ret = __skadi_cap_ops_create(input_token_ptr, &restriction, direction, new_segment_length, permissions, capability_type, output);

    return ret;
}
#if defined(CONFIG_SKADI_DEBUG)
static bool __skadi_cap_ops_derive(const void *input_token_ptr, skadi_restriction_t *restriction, const uint64_t new_segment_length, const uint64_t parent_offset,
    skadi_permission_type_t permissions, skadi_capability_type_t capability_type, void **output){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);
    DECLARE_INIT_CYCLES_COUNT(derive);

    timeout = 0;

    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();
    
    __ASSERT_NO_MSG(new_segment_length);

    LOG_DBG("Running capability derivation with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d new segment length %"PRIu64" parent offset %"PRIu64" read permission %d write permission %d execute permission %d!\n", input_token, restriction->restriction_body.task_id_body.restriction_device, restriction->restriction_body.task_id_body.restriction_task, restriction->restriction_type != SKADI_RESTRICTIONS_NONE, new_segment_length, parent_offset, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - last operation stuck! Current control status register %lx!\n",csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
    }

    // relative order of input token and restriction does not matter
    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token);

    // no restriction is default - no write necessary
    if(restriction->restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(*restriction);
        csr_write(SKADI_CAP_OPS_CSR_RESTRICTION, new_restriction);
    }

    if(parent_offset){
        // default 0
        // lower 32 bit are parent offset
        // upper 32 bit are currently reserved
        csr_write(SKADI_CAP_OPS_CSR_AUX1, parent_offset);
    }

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_DERIVE;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_TLB ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_CACHEABLE_ACCESS ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions &  SKADI_PERMISSION_IRQ_ACCESSIBLE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS;
    /* lock is not valid */
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_EXECUTE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_WRITE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | (permissions & SKADI_PERMISSION_READ ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS;


    new_ctrl_status = new_ctrl_status | (restriction->restriction_type != SKADI_RESTRICTIONS_NONE ? 1UL : 0UL) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) new_segment_length) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_NEW_SEGMENT_LENGTH_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t)capability_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS;
    new_ctrl_status = new_ctrl_status | ((uint64_t) restriction->restriction_type) << SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS;

    LOG_DBG("New restriction comes to %"PRIx64" new control to %"PRIx64"\n",new_restriction, new_ctrl_status);

    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        skadi_cap_ops_interrupt_unlock(irq_key);
        return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error indicated for derive! Current control status register %"PRIx64" for capability derivation with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d new segment length %"PRIu64" parent offset %"PRIu64" read permission %d write permission %d execute permission %d!\n", current_ctrl_status,  input_token, restriction->restriction_body.task_id_body.restriction_device, restriction->restriction_body.task_id_body.restriction_task, restriction->restriction_type != SKADI_RESTRICTIONS_NONE, new_segment_length, parent_offset, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);
        skadi_cap_ops_interrupt_unlock(irq_key);
        return 0;
    }


    READ_STATS_CSR(derive);

    *output = (void *) csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    LOG_DBG("Derive OK! Output token %p!\n",*output);

    skadi_cap_ops_interrupt_unlock(irq_key);


    UPDATE_CYCLES_COUNT(derive);

    return 1;
}

#else

static bool __attribute__((naked)) __skadi_cap_ops_derive(const void *input_token_ptr, skadi_restriction_t *restriction, const uint64_t new_segment_length, const uint64_t parent_offset,
    skadi_permission_type_t permissions, skadi_capability_type_t cap_type, void **output) {
#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS
        (void)skadi_failed_occupied_checks_derive_ops;
        (void)skadi_cycles_derive_ops;
        (void)skadi_cycles_derive;
#endif
        __asm__(
            "li t0, " STRINGIFY(1<<IRQ_M_TIMER)"\n\t"
            "csrrc t0, mie, t0\n\t" /* disable and get old value, atomically */
            "csrr t1," STRINGIFY(SKADI_CAP_OPS_CSR_CTRL_STATUS)"\n\t"
            "li t2, "STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK)"\n\t"
            "and t1, t1, t2\n\t"
            "bnez t1, fail_derive\n\t"
            "csrw " STRINGIFY(SKADI_CAP_OPS_CSR_INPUT) ", %0\n\t"
            "ld t5, 8(%1)\n\t" /* restriction type */
            "li t4, 0\n\t" /* restriction enable flag */
            "beqz t5, restr_set_derive\n\t"
            "li t4, 1\n\t" /* restriction enable flag */
            "ld t2, 0(%1)\n\t" /* assumes that layout matches exactly */
            "csrw " STRINGIFY(SKADI_CAP_OPS_CSR_RESTRICTION) ", t2\n\t"
            "restr_set_derive:\n\t"
            "csrw " STRINGIFY(SKADI_CAP_OPS_CSR_AUX1) ", %3\n\t"
            "li t1, " STRINGIFY(SKADI_CAPABILITY_OPS_OPERATION_DERIVE) "\n\t"
            "mv t3, %4\n\t" /* modifieable copy of permissions */
            ""
            "andi t2, t3, 0x1\n\t" /* get read permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply read */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get write permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply write */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get execute permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply execute */
            "srli t3, t3, 0x2\n\t" /* advance permission, ignoring lockable too */
            ""
            "andi t2, t3, 0x1\n\t" /* get IRQ accessible permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply IRQ accessible */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get cacheable TLB permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply cacheable TLB */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "andi t2, t3, 0x1\n\t" /* get cacheable access permission */
            "slli t2, t2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply cacheable access */
            "srli t3, t3, 0x1\n\t" /* advance permission */
            ""
            "slli t4, t4," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS) "\n\t"
            "or t1, t1, t4\n\t" /* apply restriction enabled */
            ""
            "slli t2, %2, " STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_NEW_SEGMENT_LENGTH_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply segment lenght */
            ""
            "slli t2, %6," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS) "\n\t"
            "or t1, t1, t2\n\t" /* apply capability type*/
            ""
            "slli t5, t5," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS) "\n\t"
            "or t1, t1, t5\n\t" /* apply restriction type */
            ""
            "csrw " STRINGIFY(SKADI_CAP_OPS_CSR_CTRL_STATUS) ", t1\n\t" /* start operation */
            "li t1," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) "\n\t"
            "status_check_loop_derive:\n\t"
            "csrr t2, " STRINGIFY(SKADI_CAP_OPS_CSR_CTRL_STATUS) "\n\t"
            "and t3, t2, t1\n\t"
            "beqz t3, status_check_loop_derive\n\t" /* still ongoing */
            "li t1," STRINGIFY(SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK)"\n\t"
            "and t3, t2, t1\n\t"
            "bnez t3, fail_derive\n\t"
            ::"r"(input_token_ptr),"r"(restriction),"r"(new_segment_length),"r"(parent_offset),"r"(permissions),"r"(output),"r"(cap_type)
            :"t0","t1","t2","t3","t4","t5","t6","a0"
        );
#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS
        __asm__ (
            "csrr a0, " STRINGIFY(SKADI_CAP_OPS_CSR_STATS)"\n\t"
            "srli a0, a0, 32\n\t" /* high 32 bits */
            "ld t1, .skadi_cycles_derive_ops_reloc\n\t"
            "amoadd.d zero, a0, 0(t1)\n\t"
            :::"a0","t1"
        );
#endif
        __asm__(
            "li a0, 1\n\t"
            "csrr t1, " STRINGIFY(SKADI_CAP_OPS_CSR_OUTPUT) "\n\t"
            "sd t1, 0(%5)\n\t"
            "csrs mie, t0\n\t"
            "ret\n\t"
            "fail_derive:\n\t"
            "ebreak\n\t"
            ::"r"(input_token_ptr),"r"(restriction),"r"(new_segment_length),"r"(parent_offset),"r"(permissions),"r"(output),"r"(cap_type)
            :"t0","t1","t2","t3","t4","t5","t6","a0"
        );
#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS
        __asm__(
            ".p2align 3\n\t"
            ".skadi_cycles_derive_ops_reloc:\n\t"
            ".dword skadi_cycles_derive_ops\n\t"
        );
#endif
}
#endif

static inline bool skadi_cap_ops_derive(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t new_segment_length, const uint32_t parent_offset,
    skadi_permission_type_t permissions, void **output) {
        skadi_capability_type_t capability_type = skadi_allocator_appropriate_capability_type_for_size(new_segment_length);
        bool ret;

        ret = __skadi_cap_ops_derive(input_token_ptr, &restriction, new_segment_length, parent_offset, permissions, capability_type, output);

        return ret;
}

static inline bool skadi_cap_ops_derive_min_cap_type(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t new_segment_length, const uint32_t parent_offset,
    skadi_permission_type_t permissions, skadi_capability_type_t min_type, void **output){
        skadi_capability_type_t capability_type = skadi_allocator_appropriate_capability_type_for_size(new_segment_length);
        bool ret;
    
        capability_type = skadi_pick_larger_capability_type(capability_type, min_type);
    
        ret = __skadi_cap_ops_derive(input_token_ptr, &restriction, new_segment_length, parent_offset, permissions, capability_type, output);

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
    uint64_t new_ctrl_status, current_ctrl_status;
    unsigned int timeout;
    int irq_key;
    DECLARE_INIT_CYCLES_COUNT(drop);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    timeout = 0;

    LOG_DBG("Running capability drop with input token %"PRIx64"!\n", input_token);

    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        /* TODO gcc does not like this line for some reason */
        /* LOG_ERR("Error - last operation stuck! Current control status register %lx!\n", csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)); */
    
    }

    // relative order of input token and restriction does not matter
    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token);

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_DROP;

    LOG_DBG("New control is %"PRIx64"\n", new_ctrl_status);

    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");
    
    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        __asm__ volatile("ebreak");
        /* TODO gcc does not like this line for some reason */
        /* LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n",current_ctrl_status); */
        skadi_cap_ops_interrupt_unlock(irq_key);
        return 0;
    }

    READ_STATS_CSR(drop);
    
    // need to force a read to the output to acknowledge end-of-operation in the ops module
    (void)csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Drop OK!");

    UPDATE_CYCLES_COUNT(drop);

    return 1;
}

static inline bool skadi_cap_ops_merge_noinspect(const void *input_token_left_ptr, const void *input_token_right_ptr, skadi_restriction_t restriction,
    skadi_permission_type_t permissions, skadi_capability_type_t capability_type, void **output){
    const uint64_t input_token_left = (uint64_t) input_token_left_ptr, input_token_right = (uint64_t) input_token_right_ptr;
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    DECLARE_INIT_CYCLES_COUNT(merge);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    timeout = 0;

    LOG_DBG("Running capability merge with input token %"PRIx64" and %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d read permission %d write permission %d execute permission %d lockable permission %d irq accessible permission %d cacheable TLB permission %d cacheable access permission %d!\n", input_token_left, input_token_right, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE, permissions & SKADI_PERMISSION_LOCKABLE, permissions & SKADI_PERMISSION_IRQ_ACCESSIBLE, permissions & SKADI_PERMISSION_CACHEABLE_TLB, permissions & SKADI_PERMISSION_CACHEABLE_ACCESS);

    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
    LOG_ERR("Error - last operation stuck! Current control status register %lx!\n", csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
    }

    // relative order of input token and restriction does not matter
    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token_left);

    // no restriction is default - no write necessary
    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        csr_write(SKADI_CAP_OPS_CSR_RESTRICTION, new_restriction);
    }

    csr_write(SKADI_CAP_OPS_CSR_AUX1, input_token_right);

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

    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
    timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        __asm__ volatile("ebreak");
    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
    return 0;
    }


    READ_STATS_CSR(merge);

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        __asm__ volatile("ebreak");

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_ERR("Error indicated for merge! Current control status register %"PRIx64"!\n", current_ctrl_status);
    return 0;
    }

    *output =  (void*) csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Merge OK! Output token %p!\n",*output);

    UPDATE_CYCLES_COUNT(merge);

    return 1;
}

static inline bool skadi_cap_ops_merge(const void *input_token_left_ptr, const void *input_token_right_ptr, skadi_restriction_t restriction,
                                            skadi_permission_type_t permissions, void **output){
    skadi_inspect_metadata_t left_metadata, right_metadata;
    skadi_capability_type_t capability_type;
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    if(skadi_cap_ops_inspect(input_token_left_ptr, &left_metadata) == false || skadi_cap_ops_inspect(input_token_right_ptr, &right_metadata) == false){
        __asm__ volatile("ebreak");
        LOG_ERR("Could not inspect inputs!");
        return false;
    }

    __ASSERT((uintptr_t)left_metadata.capability_base + (uintptr_t) left_metadata.capability_length == (uintptr_t) right_metadata.capability_base, "Expected left capability with start %"PRIu32" size %"PRIu32" to be adjacent with right capabiltiy start %"PRIu32" length %"PRIu32"!", left_metadata.capability_base, left_metadata.capability_length, right_metadata.capability_base, right_metadata.capability_length);

    capability_type = skadi_allocator_appropriate_capability_type_for_size(left_metadata.capability_length + right_metadata.capability_length);

    return skadi_cap_ops_merge_noinspect(input_token_left_ptr, input_token_right_ptr, restriction, permissions, capability_type, output);
}

static inline bool skadi_cap_ops_clone(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    skadi_capability_type_t capability_type = skadi_get_capability_type(input_token_ptr);
    DECLARE_INIT_CYCLES_COUNT(clone);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    timeout = 0;

    LOG_DBG("Running capability clone with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d read permission %d write permission %d execute permission %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - last operation stuck! Current control status register %lx!\n", csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
    }

    // relative order of input token and restriction does not matter
    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token);

    // no restriction is default - no write necessary
    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        csr_write(SKADI_CAP_OPS_CSR_RESTRICTION, new_restriction);
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

    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        __asm__ volatile("ebreak");
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    READ_STATS_CSR(clone);

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        __asm__ volatile("ebreak");
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for clone! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    *output =  (void*) csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Clone OK! Output token %p!\n",*output);

    UPDATE_CYCLES_COUNT(clone);

    return 1;
}



static inline bool skadi_cap_ops_revoke(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int irq_key;
    skadi_capability_type_t capability_type = skadi_get_capability_type(input_token_ptr);
    DECLARE_INIT_CYCLES_COUNT(revoke);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    LOG_DBG("Running capability revocation with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d read permission %d write permission %d execute permission %d lockable permission %d irq accessible %d cacheable TLB permission %d cacheable access permission %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE, permissions & SKADI_PERMISSION_LOCKABLE, permissions & SKADI_PERMISSION_IRQ_ACCESSIBLE, permissions & SKADI_PERMISSION_CACHEABLE_TLB, permissions & SKADI_PERMISSION_CACHEABLE_ACCESS);
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - last operation stuck! Current control status register %lx!\n", csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
    }

    // relative order of input token and restriction does not matter
    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token);

    // no restriction is default - no write necessary
    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        csr_write(SKADI_CAP_OPS_CSR_RESTRICTION, new_restriction);
    }

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_REVOKE;
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

    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    /* no timeout - can take a while for large capabilities */
    while(((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0);

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        __asm__ volatile("ebreak");
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for revoke! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    READ_STATS_CSR(revoke);


    *output = (void*) csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Revoke OK! Output token %p!\n",*output);

    UPDATE_CYCLES_COUNT(revoke);

    return 1;
}


static inline bool skadi_cap_ops_lock(const void *input_token_ptr, skadi_restriction_t restriction, skadi_permission_type_t permissions, void **output){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    skadi_capability_type_t capability_type = skadi_get_capability_type(input_token_ptr);
    DECLARE_INIT_CYCLES_COUNT(lock);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    timeout = 0;

    // sanity check for Skadi OS
    if(input_token < 0xffff){
        __asm__ volatile("ebreak");
        LOG_ERR("Refusing to lock root cap!");
        return false;
    }

    LOG_DBG("Running capability locking with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d read permission %d write permission %d execute permission %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - last operation stuck! Current control status register %lx!\n", csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
    }

    // relative order of input token and restriction does not matter
    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token);

    // no restriction is default - no write necessary
    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        csr_write(SKADI_CAP_OPS_CSR_RESTRICTION, new_restriction);
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

    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        __asm__ volatile("ebreak");
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        __asm__ volatile("ebreak");
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for lock! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }


    READ_STATS_CSR(lock);

    *output = (void*) csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    if(!*output){
        __asm__ volatile("ebreak");
        LOG_ERR("Internal error in operations module - lock output token is 0!");
        return 0;
    }

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Lock OK! Output token %p!\n",*output);

    UPDATE_CYCLES_COUNT(lock);

    return 1;
}

static inline bool skadi_cap_ops_restrict(const void *input_token_ptr, skadi_restriction_t restriction, const uint32_t segment_length_subtrahend, const uint32_t offset_addend, skadi_permission_type_t permissions){
    const uint64_t input_token = (uint64_t) input_token_ptr;
    uint64_t new_restriction, new_ctrl_status, current_ctrl_status;
    unsigned int timeout, irq_key;
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    DECLARE_INIT_CYCLES_COUNT(restrict);

    timeout = 0;

    LOG_DBG("Running capability restrict with input token %"PRIx64" restriction device %"PRIu16" restriction task %"PRIu32" restriction enabled %d segment length subtrahend %"PRIu32" offset addend %"PRIu32" read permission %d write permission %d execute permission %d!\n", input_token, restriction.restriction_body.task_id_body.restriction_device, restriction.restriction_body.task_id_body.restriction_task, restriction.restriction_type != SKADI_RESTRICTIONS_NONE, segment_length_subtrahend, offset_addend, permissions & SKADI_PERMISSION_READ, permissions & SKADI_PERMISSION_WRITE, permissions & SKADI_PERMISSION_EXECUTE);
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - last operation stuck! Current control status register %lx!\n", csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
    }

    // relative order of input token and restriction does not matter
    csr_write(SKADI_CAP_OPS_CSR_INPUT, input_token);

    // no restriction is default - no write necessary
    if(restriction.restriction_type != SKADI_RESTRICTIONS_NONE){
        new_restriction = skadi_encode_restriction(restriction);
        csr_write(SKADI_CAP_OPS_CSR_RESTRICTION, new_restriction);
    }

    if(offset_addend){
        // default 0
        // lower 32 bit are offset addend
        // upper 32 bit are currently reserved
        csr_write(SKADI_CAP_OPS_CSR_AUX1, offset_addend);
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

    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    while(timeout < SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES && ((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0){
        timeout ++;
    }

    if(timeout == SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES){
        __asm__ volatile("ebreak");
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error - timeout! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    READ_STATS_CSR(restrict);

    LOG_DBG("Current control status register is %lx!\n", csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        __asm__ volatile("ebreak");
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for restrict! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }
    
    // need to force a read to the output to acknowledge end-of-operation in the ops module
    (void) csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Restrict OK!");

    UPDATE_CYCLES_COUNT(restrict);

    return 1;
}


static inline bool skadi_cap_ops_sweep(void){
        uint64_t new_ctrl_status, current_ctrl_status;
    unsigned int irq_key;
    DECLARE_INIT_CYCLES_COUNT(sweep);
    LOG_MODULE_DECLARE(skadi_ops_driver, CONFIG_SKADI_LOG_LEVEL);

    LOG_DBG("Running capability sweep!");
    
    // prevent someone from stealing our token or interfering with our interaction with the ops module
    irq_key = skadi_cap_ops_interrupt_lock();

    if((csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK) != 0){
        __asm__ volatile("ebreak");
        LOG_ERR("Error - last operation stuck! Current control status register %lx!\n", csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS));
    }

    new_ctrl_status = SKADI_CAPABILITY_OPS_OPERATION_SWEEP;
    
    csr_write(SKADI_CAP_OPS_CSR_CTRL_STATUS, new_ctrl_status);

    LOG_DBG("Waiting for capability operations to be done!\n");

    /* no timeout - can take a while for large capabilities */
    while(((current_ctrl_status = csr_read(SKADI_CAP_OPS_CSR_CTRL_STATUS)) & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK) == 0);

    LOG_DBG("Current control status register is %"PRIx64"!\n", current_ctrl_status);

    if((current_ctrl_status & SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK) != 0){
        __asm__ volatile("ebreak");
        
        skadi_cap_ops_interrupt_unlock(irq_key);

        LOG_ERR("Error indicated for revoke! Current control status register %"PRIx64"!\n", current_ctrl_status);
        return 0;
    }

    READ_STATS_CSR(sweep);


    (void)csr_read(SKADI_CAP_OPS_CSR_OUTPUT);

    skadi_cap_ops_interrupt_unlock(irq_key);

    LOG_DBG("Unseal OK!\n");

    UPDATE_CYCLES_COUNT(sweep);

    return 1;
}


static inline uint64_t skadi_cap_ops_get_capability_count(void){

    return csr_read(SKADI_CAP_OPS_CSR_CAP_COUNT) & SKADI_CAP_OPS_COUNT_COUNT_MASK;
}

static inline bool skadi_cap_ops_get_northcape_enabled(void){

    return csr_read(SKADI_CAP_OPS_CSR_CAP_COUNT) & SKADI_CAP_OPS_COUNT_NORTHCAPE_ENABLE_STATUS_MASK;
}

/* can only be enabled once with no way to go back */
static inline void skadi_cap_ops_set_northcape_enabled(void){

    csr_write(SKADI_CAP_OPS_CSR_CAP_COUNT, SKADI_CAP_OPS_COUNT_NORTHCAPE_ENABLE_STATUS_MASK);
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
    uint64_t ret;

    do {
        /* the hardware ensures that each 64-bit sequence is only returned in a single 64-bit read; read value is 0 when no RNG bits available*/
        ret = csr_read(SKADI_CAP_OPS_CSR_TRNG);
    } while(!ret);
    
    return ret;
}

#pragma GCC diagnostic pop

#ifndef SKADI_SUBSYSTEM_H
/* dependency conflict */
#include <zephyr/skadi/skadi_irq.h>
#endif

#endif /* SKADI_OPS_DRIVER_CSR_H */
