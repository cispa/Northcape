#ifndef SKADI_OPS_CONSTANTS_H
#define SKADI_OPS_CONSTANTS_H

#if !defined(_ASMLANGUAGE)

#include <stdbool.h>
#include <stdint.h>
#include <zephyr/sys/util.h>
#include <zephyr/arch/riscv/csr.h>
#endif /* !_ASMLANGUAGE */

#define SKADI_DEVICE_ID_CPU 0
#define SKADI_TASK_ID_LOADER 0
#define SKADI_NONSTANDARD_MSTATUS_ISR_SHIFT 23

#define SKADI_PERF_COUNTER_EVENT_ID_L1_INSTR_MISS       23
#define SKADI_PERF_COUNTER_EVENT_ID_L1_DATA_MISS        24
#define SKADI_PERF_COUNTER_EVENT_ID_L2_RESOLVER_MISS    25
#define SKADI_PERF_COUNTER_EVENT_ID_L2_OPS_MISS         26
#define SKADI_PERF_COUNTER_EVENT_ID_EXTRA_ICACHE_DELAY  27
#define SKADI_PERF_COUNTER_EVENT_ID_MISSUNIT_STALL      28
#define SKADI_PERF_COUNTER_EVENT_ID_OPS_WRITE_STALL     29
#define SKADI_PERF_COUNTER_EVENT_ID_L2_FULL_WIPE        30

#define SKADI_PERF_COUNTER_CONFIGURE_L1_INSTR_MISS()      csr_write(mhpmevent3, SKADI_PERF_COUNTER_EVENT_ID_L1_INSTR_MISS)
#define SKADI_PERF_COUNTER_CONFIGURE_L1_DATA_MISS()       csr_write(mhpmevent4, SKADI_PERF_COUNTER_EVENT_ID_L1_DATA_MISS)
#define SKADI_PERF_COUNTER_CONFIGURE_L2_RESOLVER_MISS()   csr_write(mhpmevent5, SKADI_PERF_COUNTER_EVENT_ID_L2_RESOLVER_MISS)
#define SKADI_PERF_COUNTER_CONFIGURE_L2_OPS_MISS()        csr_write(mhpmevent6, SKADI_PERF_COUNTER_EVENT_ID_L2_OPS_MISS)
#define SKADI_PERF_COUNTER_CONFIGURE_EXTRA_ICACHE_DELAY() csr_write(mhpmevent7, SKADI_PERF_COUNTER_EVENT_ID_EXTRA_ICACHE_DELAY)
#define SKADI_PERF_COUNTER_CONFIGURE_MISSUNIT_STALL()     csr_write(mhpmevent8, SKADI_PERF_COUNTER_EVENT_ID_MISSUNIT_STALL)
#define SKADI_PERF_COUNTER_CONFIGURE_OPS_WRITE_STALL()    csr_write(mhpmevent9, SKADI_PERF_COUNTER_EVENT_ID_OPS_WRITE_STALL)
#define SKADI_PERF_COUNTER_CONFIGURE_L2_FULL_WIPE()       csr_write(mhpmevent9, SKADI_PERF_COUNTER_EVENT_ID_L2_FULL_WIPE)


#define SKADI_PERF_COUNTER_READ_L1_INSTR_MISS()      csr_read(mhpmcounter3)
#define SKADI_PERF_COUNTER_READ_L1_DATA_MISS()       csr_read(mhpmcounter4)
#define SKADI_PERF_COUNTER_READ_L2_RESOLVER_MISS()   csr_read(mhpmcounter5)
#define SKADI_PERF_COUNTER_READ_L2_OPS_MISS()        csr_read(mhpmcounter6)
#define SKADI_PERF_COUNTER_READ_EXTRA_ICACHE_DELAY() csr_read(mhpmcounter7)
#define SKADI_PERF_COUNTER_READ_MISSUNIT_STALL()     csr_read(mhpmcounter8)
#define SKADI_PERF_COUNTER_READ_OPS_WRITE_STALL()    csr_read(mhpmcounter9)
#define SKADI_PERF_COUNTER_READ_L2_FULL_WIPE()       csr_read(mhpmcounter9)


#define SKADI_MTIMER_HOOK_CSR 0x7ff


/* 32-bit offset capability token with mac, id 0 */
#define SKADI_ROOT_CAP_UPPER_LIMIT 0xffffffff

#define SKADI_ROOT_CAP_TOKEN NULL

#if !defined(_ASMLANGUAGE)

static inline bool skadi_is_in_isr(void){
    return (csr_read(mstatus) & (1<<SKADI_NONSTANDARD_MSTATUS_ISR_SHIFT)) != 0;
}


typedef enum {
    SKADI_CAPABILITY_TYPE_OFFSET_32_BIT=0x0,
    SKADI_CAPABILITY_TYPE_OFFSET_8_BIT=0x1,
    SKADI_CAPABILITY_TYPE_OFFSET_16_BIT=0x2,
    SKADI_CAPABILITY_TYPE_OFFSET_24_BIT=0x3
} skadi_capability_type_t;

typedef enum {
    SKADI_RESTRICTIONS_NONE=0x0,
    SKADI_RESRICTIONS_DEVICE_INTERPRETED=0x1,
    SKADI_RESTRICTIONS_TASK_ID_BOUND=0x2,
    SKADI_RESTRICTIONS_SET_TASK_ID=0x3    
} skadi_restriction_type_t;

typedef enum {
    SKADI_PERMISSION_READ = BIT(0),
    SKADI_PERMISSION_WRITE = BIT(1),
    SKADI_PERMISSION_EXECUTE = BIT(2),
    SKADI_PERMISSION_LOCKABLE = BIT(3),
    SKADI_PERMISSION_IRQ_ACCESSIBLE = BIT(4),
    SKADI_PERMISSION_CACHEABLE_TLB = BIT(5),
    SKADI_PERMISSION_CACHEABLE_ACCESS = BIT(6)
} skadi_permission_type_t;

#define SKADI_ALL_PERMISSIONS (SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS)

/* this memory layout EXACTLY matches operations module alignment expectations - do not modify layout!*/
typedef struct {
    union {
        struct {
            uint32_t restriction_task;
            uint16_t restriction_device;
            uint16_t reserved;
        } task_id_body;
        uint64_t device_interpreted;
    } restriction_body;
    skadi_restriction_type_t restriction_type;
} __attribute__((__packed__)) skadi_restriction_t;

#define SKADI_TASK_ID_RESTRICTION(TASK, DEVICE, RESTRICTION_TYPE) { .restriction_body.task_id_body.restriction_task=TASK, .restriction_body.task_id_body.restriction_device=DEVICE, .restriction_type=RESTRICTION_TYPE}
#define SKADI_TASK_ID_BOUND_RESTRICTION(TASK, DEVICE) SKADI_TASK_ID_RESTRICTION(TASK, DEVICE, SKADI_RESTRICTIONS_TASK_ID_BOUND)

#define SKADI_NO_RESTRICTION {.restriction_type=SKADI_RESTRICTIONS_NONE}

typedef uint32_t skadi_task_id_t;
typedef uint16_t skadi_device_id_t;

#define SKADI_ISR_TABLE_SIZE 256

// MMIO access
    // we want to access the fields using single bus transactions
    // we rely on the compiler to generate ALIGNED accesses
    typedef struct __attribute__((aligned(8))) {
        volatile uint64_t input_token_reg;
        volatile uint64_t output_reg;
        volatile uint64_t restriction_reg;
        volatile uint64_t control_status_reg;
        volatile uint64_t aux1_reg;
        volatile uint64_t capability_count;
        volatile uint64_t trng;
    } skadi_cap_ops_regs_t;

    #define SKADI_CAP_OPS_CSR_INPUT         0x7f0
    #define SKADI_CAP_OPS_CSR_OUTPUT        0x7f1
    #define SKADI_CAP_OPS_CSR_RESTRICTION   0x7f2
    #define SKADI_CAP_OPS_CSR_CTRL_STATUS   0x7f3
    #define SKADI_CAP_OPS_CSR_AUX1          0x7f4
    #define SKADI_CAP_OPS_CSR_CAP_COUNT     0x7f5
    #define SKADI_CAP_OPS_CSR_TRNG          0x7f6
    #define SKADI_CAP_OPS_CSR_STATS         0x7f7

    typedef struct {        
        union {
            struct {
                uint32_t restriction_task_id;
                uint16_t restriction_device_id;
            } task_restriction;
            uint64_t device_specific_restriction;
        } restriction_body;

        skadi_restriction_type_t restriction_type;

        uint32_t capability_length;
        uint32_t capability_base;

        uint16_t refcount;

        bool read_permission;
        bool write_permission;
        bool execute_permission;
        bool lockable_permission;
        bool irq_accessible_permission;
    } skadi_inspect_metadata_t;

    // restriction register
    #define SKADI_CAP_OPS_RESTRICTION_REGISTER_DEVICE_ID_SHIFT_BITS                 32

    // control / status register
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IRQ_ACCESSIBLE_PERMISSION_SHIFT_BITS 5
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_LOCKABLE_PERMISSION_SHIFT_BITS       6
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_EXECUTE_PERMISSION_SHIFT_BITS        7
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_WRITE_PERMISSION_SHIFT_BITS          8
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_READ_PERMISSION_SHIFT_BITS           9
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_TLB_SHIFT_BITS             49
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_CACHEABLE_ACCESS_SHIFT_BITS          50
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_VIRT_PCR_SHIFT_BITS                  51

    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTRICTION_ENABLED_SHIFT_BITS       10
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_NEW_SEGMENT_LENGTH_SHIFT_BITS        11
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_DIRECTION_SHIFT_BITS                 43
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_TYPE_SHIFT_BITS                      44
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_RESTR_TYPE_SHIFT_BITS                46

    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_COMPLETE_MASK                        (1UL<<63)
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_IN_PROGRESS_MASK                     (1UL<<62)
    #define SKADI_CAP_OPS_CTRL_STATUS_REGISTER_ERROR_MASK                           (1UL<<61)
    

    #define SKADI_CAP_OPS_COUNT_NORTHCAPE_ENABLE_STATUS_MASK                        ((1UL << 63) | 1UL << 62)
    #define SKADI_CAP_OPS_COUNT_COUNT_MASK                                          (~((1UL << 63) | 1UL << 62))

    

    #define SKADI_CAPABILITY_OPS_OPERATION_CREATE               0x0
    #define SKADI_CAPABILITY_OPS_OPERATION_DERIVE               0x1
    #define SKADI_CAPABILITY_OPS_OPERATION_DROP                 0x2
    #define SKADI_CAPABILITY_OPS_OPERATION_MERGE                0x3
    #define SKADI_CAPABILITY_OPS_OPERATION_CLONE                0x4
    #define SKADI_CAPABILITY_OPS_OPERATION_REVOKE               0x5
    #define SKADI_CAPABILITY_OPS_OPERATION_LOCK                 0x6
    #define SKADI_CAPABILITY_OPS_OPERATION_INSPECT              0x7
    #define SKADI_CAPABILITY_OPS_OPERATION_RESTRICT             0x8
    #define SKADI_CAPABILITY_OPS_OPERATION_SWEEP                0xb
#ifdef CONFIG_SKADI_OPS_MODULE_CSRS
    // quicker access -> need to wait longer
    #define SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES ((unsigned int)-1)
#else
    #define SKADI_CAPABILITY_OPS_OPERATION_TIMEOUT_CYCLES 4096
#endif

    #define SKADI_ROOT_CAPABILITY 0x0

__attribute__ ((const)) static inline bool skadi_token_is_root_capability(const void* token){
    return token <= (void*)SKADI_ROOT_CAP_UPPER_LIMIT;
}

__attribute__ ((const)) static inline skadi_capability_type_t skadi_allocator_appropriate_capability_type_for_size(uint32_t size){
    if(size < (1<<8)){
        return SKADI_CAPABILITY_TYPE_OFFSET_8_BIT;
    }
    if(size < (1<<16)){
        return SKADI_CAPABILITY_TYPE_OFFSET_16_BIT;
    }
    if(size < (1<<24)){
        return SKADI_CAPABILITY_TYPE_OFFSET_24_BIT;
    }
    return SKADI_CAPABILITY_TYPE_OFFSET_32_BIT;
}

__attribute__ ((const)) static inline size_t skadi_capability_type_to_max_size_clog2(skadi_capability_type_t cap){
    switch(cap){
        case SKADI_CAPABILITY_TYPE_OFFSET_8_BIT:
            return 8;
        case SKADI_CAPABILITY_TYPE_OFFSET_16_BIT:
            return 16;
        case SKADI_CAPABILITY_TYPE_OFFSET_24_BIT:
            return 24;
        default:
            return 32;
    }
}

__attribute__ ((const)) static inline skadi_capability_type_t skadi_pick_larger_capability_type(skadi_capability_type_t cap_a, skadi_capability_type_t cap_b){
    if(skadi_capability_type_to_max_size_clog2(cap_a) > skadi_capability_type_to_max_size_clog2(cap_b)){
        return cap_a;
    }
    return cap_b;
}

__attribute__ ((const)) static inline skadi_capability_type_t skadi_get_capability_type(const void* token){
    const uint64_t token_num = (uint64_t) token;
    const uint64_t token_start_bits = token_num >> 62;

    return token_start_bits;
}

__attribute__ ((const)) static inline uint32_t skadi_get_capability_offset(const void* token){
    const uint64_t token_num = (uint64_t) token;
    const skadi_capability_type_t token_type = skadi_get_capability_type(token);

    switch(token_type){
        case SKADI_CAPABILITY_TYPE_OFFSET_32_BIT:
            return token_num & 0xffffffff; /* 32 bits */
        case SKADI_CAPABILITY_TYPE_OFFSET_16_BIT:
            return token_num & 0xffff; /* 16 bits */
        case SKADI_CAPABILITY_TYPE_OFFSET_24_BIT:
            return token_num & 0xffffff; /* 24 bits */
        /* must be 8 bits */
        default:
            return token_num & 0xff; /* 8 bits */
    }
}

__attribute__ ((const)) static inline bool skadi_is_same_capability(const void *cap1, const void *cap2){
    uintptr_t token_1 = (uintptr_t) cap1;
    uintptr_t token_2 = (uintptr_t) cap2;

    token_1 -= skadi_get_capability_offset(cap1);
    token_2 -= skadi_get_capability_offset(cap2);

    return token_1 == token_2;
}

#ifdef CONFIG_SKADI_OS
/* moved here due to include conflict */
struct skadi_subsystem_stack {
    uint8_t stack[CONFIG_SKADI_SUBSYSTEM_STACK_SIZE+1];
};
#endif

#endif /* !_ASMLANGUAGE */


#endif
