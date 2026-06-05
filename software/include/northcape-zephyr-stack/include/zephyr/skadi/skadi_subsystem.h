#ifndef SKADI_SUBSYSTEM_H
#define SKADI_SUBSYSTEM_H
    #include <stdint.h>
    #include <stdarg.h>
    #include <zephyr/skadi/skadi_asm.h>
    #include <zephyr/skadi/skadi_ops_driver.h>

    #ifndef CONFIG_SKADI_SUBSYSTEM_STACK_SIZE
    #error Need CONFIG_SKADI_SUBSYSTEM_STACK_SIZE
    #endif

/* to resolve a circular dependency with allocator init */

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"

#ifdef SKADI_SUBSYSTEM_ALLOCATOR
static inline void *skadi_allocator_alloc(uint32_t requested_size, skadi_permission_type_t permissions);
bool skadi_allocator_free(void *token);
#else
static inline void *skadi_allocator_alloc(uint32_t requested_size, skadi_permission_type_t permissions);
static inline bool skadi_allocator_free(void *token);
#endif
static inline void *skadi_allocator_alloc_rw(uint32_t requested_size);
static inline void *skadi_allocator_realloc(void *ptr, size_t size);

#pragma GCC diagnostic pop

#ifdef SKADI_SUBSYSTEM
/* ##__VA_ARGS behind a comma is a GNU extension, allowing us to omit the comma if no variadic args */
static inline  __attribute__ ((__always_inline__)) int __skadi_printf(const char *format, const char *file, int line, ...);
#if CONFIG_SKADI_LOG_LEVEL == LOG_LEVEL_DBG
    #define SKADI_SUBSYSTEM_DEBUG(fmt, ...) __skadi_printf("D: " fmt "\n", __FILE__, __LINE__, ##__VA_ARGS__)
#else
    #define SKADI_SUBSYSTEM_DEBUG(fmt, ...) do{ } while(0)
#endif
#else
#if CONFIG_SKADI_LOG_LEVEL == LOG_LEVEL_DBG
    #define SKADI_SUBSYSTEM_DEBUG(fmt, ...) printk("D: " fmt "\n", ##__VA_ARGS__)
#else
    #define SKADI_SUBSYSTEM_DEBUG(fmt, ...) do{ } while(0)
#endif
#endif

    #define SKADI_SUBSYSTEM_ERROR(fmt, ...) printk("E: " fmt "\n", ##__VA_ARGS__)
   
#ifdef CONFIG_SKADI_RESET_BRANCH_TABLE_ON_SUBSYSTEM_CALL
    // the cva6 currently does not know when to clear the branch target prediction
    // this causes speculative fetches of branch targets from the i-cache, possibly even causing spurious subsystem calls!
    // as a work around, manually flush the branch target prediction on every subsystem call/return via custom CSR
    #define SKADI_SUBSYSTEM_FLUSH_BRANCH_TARGET_PREDICTION      \
        "csrrsi x0, 0x7C0, 2\n\t"                               \
        "fence\n\t" /* commit actual reads and writes as long as we still can*/
#else
    #define SKADI_SUBSYSTEM_FLUSH_BRANCH_TARGET_PREDICTION ""
#endif

#ifdef CONFIG_SKADI_CACHE_INTEGRATION
    /* not needed - Northcape will handle this */
    #define SKADI_SUBSYSTEM_FLUSH_CACHES ""
#else
    #define SKADI_SUBSYSTEM_FLUSH_CACHES        \
        "csrwi 0x7C0, 0x00\n\t" /* icache */    \
        "csrwi 0x7C0, 0x01\n\t"                 \
        "csrwi 0x7C1, 0x00\n\t" /* dcache */    \
        "csrwi 0x7C1, 0x01\n\t"
#endif


    #define SKADI_SUBSYSTEM_SHUFFLE_ARGUMENT_REGISTERS_LEFT \
        __asm__ volatile(                                   \
            "mv a0, a1\n\t"                                 \
            "mv a1, a2\n\t"                                 \
            "mv a2, a3\n\t"                                 \
            "mv a3, a4\n\t"                                 \
            "mv a4, a5\n\t"                                 \
            "mv a5, a6\n\t"                                 \
            "mv a6, a7\n\t"                                 \
            "li a7, 0\n\t"                                  \
        )

    /**
     * @brief Used to track which stack frame is in use at any given time.
     */
    struct skadi_subsystem_stack_manager {
        uint64_t stack_bitmap;
        uint8_t *tops_of_stack[CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS];
        struct skadi_subsystem_stack stacks[CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS];
    } __attribute__((__packed__));

    struct skadi_subsystem_stack_manager_irq {
        uint64_t stack_bitmap;
        uint8_t *tops_of_stack[CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS_IRQ];
        struct skadi_subsystem_stack stacks[CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS_IRQ];
    } __attribute__((__packed__));

    struct skadi_subsystem_context {
        // we need to bring our own stack
        // the caller will clear theirs
        // IRQ stack manager
        struct skadi_subsystem_stack_manager_irq *stack_manager_irq;
        // non-IRQ stack manager
        struct skadi_subsystem_stack_manager *stack_manager;
        // address of the C function that we want to call
        void *function_ptr_impl;

        // task ID of the subsystem
        // used to check return capability
        uint32_t subsystem_task_id;
    };    

    #define SKADI_SUBSYSTEM_STACK_ALIGNMENT 4

    /* defined in skadi_library.c */
    extern skadi_task_id_t _skadi_current_subsystem_id;
    /* the scalar value ends up in the "address..." */
    #define SKADI_CURRENT_TASK_ID _skadi_current_subsystem_id
    
    static inline uint8_t *skadi_subsystem_parse_stack(void){
        uintptr_t sp;

        // TODO this costs us a few bytes of stack
        // but we know that the stack is aligned, and we need not make any assumptions about the capability type etc.
        __asm__ volatile(
            "mv %0, sp" : "=r" (sp)
        );

        return (uint8_t *) sp;
    }

    static inline uint8_t *skadi_subsystem_prepare_allocated_stack(struct skadi_subsystem_stack *allocated_stack, uint32_t current_task_id, void **lock_holder_out){
/* loader does not need protection for its stack */
#if defined(SKADI_SUBSYSTEM)
        void* restricted_stack;
        bool alloc_ok;
#ifdef CONFIG_SKADI_DEBUG_UNRESTRICTED_STACK
        skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
#else
        skadi_restriction_t restriction = SKADI_TASK_ID_BOUND_RESTRICTION(current_task_id, SKADI_DEVICE_ID_CPU);
#endif 
#ifdef CONFIG_SKADI_SUBSYSTEM_LOCK_STACK
        alloc_ok = skadi_cap_ops_lock(allocated_stack, restriction, SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &restricted_stack);
#else
        /* location in bss segment provides protection against token leakage, but we also want overflow protection */
        alloc_ok = skadi_cap_ops_derive(allocated_stack, restriction, sizeof(*allocated_stack),  skadi_get_capability_offset(allocated_stack), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &restricted_stack);
#endif /* CONFIG_SKADI_SUBSYSTEM_LOCK_STACK */
        
        if(!alloc_ok || !restricted_stack){
            return NULL;
        }                                                                                                              

        if(lock_holder_out){
            *lock_holder_out = restricted_stack;
        }

        allocated_stack = (struct skadi_subsystem_stack *) restricted_stack;
#endif /* SKADI_SUBSYSTEM */
        /* prevent compiler warnings in case not used - build config */
        ARG_UNUSED(current_task_id);
        ARG_UNUSED(lock_holder_out);
        return &allocated_stack->stack[CONFIG_SKADI_SUBSYSTEM_STACK_SIZE+1-8];
    }
    
    /**
     * @brief Per-subsystem stack manager.
     */
    extern struct skadi_subsystem_stack_manager *skadi_subsystem_stacks;
    /**
     * @brief Per-subsystem IRQ stack manager.
     */
    extern struct skadi_subsystem_stack_manager_irq *skadi_subsystem_stacks_irq;

    static inline bool skadi_init_subsystem_stacks(struct skadi_subsystem_stack_manager *stack_manager, skadi_task_id_t current_task_id){
        struct skadi_subsystem_stack *subsystem_stack;

        // we need to allocate > 1 stack frames for callee stack frames
        // otherwise, in scenarios where a callee trampoline makes a subsystem call which in turn makes a subsystem call back into the callee trampoline's task,
        // we re-use the stack and overwrite it
        // however, the stack frames can be shared between all subsystem calls
        // so we only need to allocate them on the first call
        
        if(!stack_manager){
            return false;
        }

        // make sure non-available stacks are always reserved -> no need to do range check in trampoline
        stack_manager -> stack_bitmap = (1ULL<<CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS)-1;

        for(int i = 0; i < CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS; i++){
            subsystem_stack = &stack_manager->stacks[i];

            stack_manager -> tops_of_stack[i] = skadi_subsystem_prepare_allocated_stack(subsystem_stack, current_task_id, NULL);

            if(((uintptr_t)stack_manager -> tops_of_stack[i]) % SKADI_SUBSYSTEM_STACK_ALIGNMENT != 0){
                return false;
            }
        }

        return true;
    }

#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
    static inline bool skadi_init_subsystem_stacks_irq(struct skadi_subsystem_stack_manager_irq *stack_manager_irq, skadi_task_id_t current_task_id){
        struct skadi_subsystem_stack *subsystem_stack;

        // we need to allocate > 1 stack frames for callee stack frames
        // otherwise, in scenarios where a callee trampoline makes a subsystem call which in turn makes a subsystem call back into the callee trampoline's task,
        // we re-use the stack and overwrite it
        // however, the stack frames can be shared between all subsystem calls
        // so we only need to allocate them on the first call
        
        if(!stack_manager_irq){
            return false;
        }

        // make sure non-available stacks are always reserved -> no need to do range check in trampoline
        stack_manager_irq -> stack_bitmap = (1ULL<<CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS_IRQ)-1;

        for(int i = 0; i < CONFIG_SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NUM_STACKS_IRQ; i++){
            subsystem_stack = &stack_manager_irq->stacks[i];

            stack_manager_irq -> tops_of_stack[i] = skadi_subsystem_prepare_allocated_stack(subsystem_stack, current_task_id, NULL);

            if(((uintptr_t)stack_manager_irq -> tops_of_stack[i]) % SKADI_SUBSYSTEM_STACK_ALIGNMENT != 0){
                return false;
            }
        }

        return true;
    }
#else
    static inline bool skadi_init_subsystem_stacks_irq(struct skadi_subsystem_stack_manager_irq *stack_manager_irq, skadi_task_id_t current_task_id){
        ARG_UNUSED(stack_manager_irq);
        ARG_UNUSED(current_task_id);
        return true;
    }
#endif

/* for fast reg zero, this is done in conjunction with the ARGUMENTS */
#if defined(CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS) || defined(CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION)
    #define SKADI_SUBSYSTEM_DESTROY_REGISTERS_EXCEPT_T1_SP_GP_FP ""
    #define SKADI_SUBSYSTEM_DESTROY_REGISTERS_EXCEPT_T1_SP_GP ""
    #define SKADI_SUBSYSTEM_DESTROY_REGISTERS ""
    #define SKADI_SUBSYSTEM_DESTROY_ARGUMENT_REGISTERS(NUM_INPUT_ARGS) /* nothing */
#else
    #define SKADI_SUBSYSTEM_DESTROY_REGISTERS_EXCEPT_T1_SP_GP_FP                                                                        \
            "mv tp,x0\n\t"                                                                                                              \
            "mv s1,x0\n\t"                                                                                                              \
            "mv s2,x0\n\t"                                                                                                              \
            "mv s3,x0\n\t"                                                                                                              \
            "mv s4,x0\n\t"                                                                                                              \
            "mv s5,x0\n\t"                                                                                                              \
            "mv s6,x0\n\t"                                                                                                              \
            "mv s7,x0\n\t"                                                                                                              \
            "mv s8,x0\n\t"                                                                                                              \
            "mv s9,x0\n\t"                                                                                                              \
            "mv s10,x0\n\t"                                                                                                             \
            "mv s11,x0\n\t"                                                                                                             \
            "mv t0,x0\n\t"                                                                                                              \
            "mv t2,x0\n\t"                                                                                                              \
            "mv t3,x0\n\t"                                                                                                              \
            "mv t4,x0\n\t"                                                                                                              \
            "mv t5,x0\n\t"                                                                                                              \
            "mv t6,x0\n\t"                                                                                                         

#ifdef CONFIG_PROFILING_PERF
    /* let the FP live on subsystem call - allows us to stack-trace beyond subsystem call boundaries */
    #define SKADI_SUBSYSTEM_DESTROY_REGISTERS_EXCEPT_T1_SP_GP \
        SKADI_SUBSYSTEM_DESTROY_REGISTERS_EXCEPT_T1_SP_GP_FP
#else
    #define SKADI_SUBSYSTEM_DESTROY_REGISTERS_EXCEPT_T1_SP_GP \
        SKADI_SUBSYSTEM_DESTROY_REGISTERS_EXCEPT_T1_SP_GP_FP \
        "mv fp,x0\n\t"
    
#endif
    #define SKADI_SUBSYSTEM_DESTROY_REGISTERS                                                                                           \
        SKADI_SUBSYSTEM_DESTROY_REGISTERS_EXCEPT_T1_SP_GP                                                                               \
            "mv gp,x0\n\t"                                                                                                              \
            "mv sp,x0\n\t"                                                                                                              \
            "mv t1,x0\n\t"                                                                                                         

#define SKADI_SUBSYSTEM_DESTROY_ARGUMENT_REGISTERS(NUM_INPUT_ARGS)          \
    if(NUM_INPUT_ARGS < 1){                                                 \
        __asm__ volatile (                                                  \
            "li a0, 0"                                                      \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS < 2){                                                 \
        __asm__ volatile (                                                  \
            "li a1, 0"                                                      \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS < 3){                                                 \
        __asm__ volatile (                                                  \
            "li a2, 0"                                                      \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS < 4){                                                 \
        __asm__ volatile (                                                  \
            "li a3, 0"                                                      \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS < 5){                                                 \
        __asm__ volatile (                                                  \
            "li a4, 0"                                                      \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS < 6){                                                 \
        __asm__ volatile (                                                  \
            "li a5, 0"                                                      \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS < 7){                                                 \
        __asm__ volatile (                                                  \
            "li a6, 0"                                                      \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS < 8){                                                 \
        __asm__ volatile (                                                  \
            "li a7, 0"                                                      \
        );                                                                  \
    }
#endif

    #define SKADI_SUBSYSTEM_RESTORE_VARIADIC_ARGUMENT_REGS(NUM_INPUT_ARGS)  \
    if(NUM_INPUT_ARGS >= 1){                                                \
        __asm__ volatile (                                                  \
            "ld a7, 56(s0)"                                                 \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS >= 2){                                                \
        __asm__ volatile (                                                  \
            "ld a6, 48(s0)"                                                 \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS >= 3){                                                \
        __asm__ volatile (                                                  \
            "ld a5, 40(s0)"                                                 \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS >= 4){                                                \
        __asm__ volatile (                                                  \
            "ld a4, 32(s0)"                                                 \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS >= 5){                                                \
        __asm__ volatile (                                                  \
            "ld a3, 24(s0)"                                                 \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS >= 6){                                                \
        __asm__ volatile (                                                  \
            "ld a2, 16(s0)"                                                 \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS >= 7){                                                \
        __asm__ volatile (                                                  \
            "ld a1, 8(s0)"                                                  \
        );                                                                  \
    }                                                                       \
    if(NUM_INPUT_ARGS >= 8){                                                \
        __asm__ volatile (                                                  \
            "ld a0, 0(s0)"                                                  \
        );                                                                  \
    }
#if defined(CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS) || defined(CONFIG_SKADI_SUBSYSTEM_CALL_INSTRUCTIONS)
    static inline void skadi_subsystem_check_function_pointer(const void* function_pointer, bool is_irq, bool accept_own_task_id){
        ARG_UNUSED(function_pointer);
        ARG_UNUSED(is_irq);
        ARG_UNUSED(accept_own_task_id);
    }
#else
    static inline void skadi_subsystem_check_function_pointer(const void* function_pointer, bool is_irq, bool accept_own_task_id){
        const char *reason;

        if(!skadi_subsystem_can_accept_function_pointer((uintptr_t)function_pointer, &reason, SKADI_CURRENT_TASK_ID, is_irq, accept_own_task_id)){
            /* TODO dependency conflict with stdio...*/
            for(;;){}
        }
    }
#endif

#if !defined(SCHEDULER_SUBSYSTEM)
    #define SKADI_SUBSYSTEM_SETUP_CALLEE_TRAMPOLINE_NOINIT(SUBSYS_ENTRY_POINT_NAME)                                                     \
        static struct skadi_subsystem_context SUBSYS_ENTRY_POINT_NAME##_context = {};                                                   \
        static inline bool SUBSYS_ENTRY_POINT_NAME##_register_init_function(void){                                                      \
            skadi_task_id_t my_task_id = SKADI_CURRENT_TASK_ID;                                                                         \
            extern uint64_t SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_context_reloc;                                                \
            extern uint64_t SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_mtimer_sched_hook_reloc;                                      \
            extern void (*SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_skadi_subsystem_yield_stub)(void);                              \
            extern void _skadi_subsystem_yield_stub(void);                                                                              \
            extern void (**skadi_subsystem_mtimer_sched_hook)(void);                                                                    \
            uint64_t *context_token = &SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_context_reloc;                                     \
            uint64_t *timer_reloc_token = &SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_mtimer_sched_hook_reloc;                       \
            SUBSYS_ENTRY_POINT_NAME##_context.function_ptr_impl = SUBSYS_ENTRY_POINT_NAME##_impl_wr;                                    \
            SUBSYS_ENTRY_POINT_NAME##_context.subsystem_task_id = my_task_id;                                                           \
            SUBSYS_ENTRY_POINT_NAME##_context.stack_manager = skadi_subsystem_stacks;                                                   \
            SUBSYS_ENTRY_POINT_NAME##_context.stack_manager_irq = IS_ENABLED(CONFIG_SKADI_SUBSYS_SYNC_UP) ?                             \
                skadi_subsystem_stacks_irq : NULL;                                                                                      \
            *context_token = (uint64_t) &SUBSYS_ENTRY_POINT_NAME##_context;                                                             \
            *timer_reloc_token = (uint64_t) skadi_subsystem_mtimer_sched_hook;                                                          \
            SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_skadi_subsystem_yield_stub = _skadi_subsystem_yield_stub;                     \
            return true; /* OK */                                                                                                       \
        }                                                                                                                               \

#else
    /* scheduler is missing 1 level of indirection, and always imports 0... */
    #define SKADI_SUBSYSTEM_SETUP_CALLEE_TRAMPOLINE_NOINIT(SUBSYS_ENTRY_POINT_NAME)                                                     \
        static struct skadi_subsystem_context SUBSYS_ENTRY_POINT_NAME##_context = {};                                                   \
        static inline bool SUBSYS_ENTRY_POINT_NAME##_register_init_function(void){                                                      \
            skadi_task_id_t my_task_id = SKADI_CURRENT_TASK_ID;                                                                         \
            extern uint64_t SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_context_reloc;                                                \
            extern uint64_t SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_mtimer_sched_hook_reloc;                                      \
            extern void (*SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_skadi_subsystem_yield_stub)(void);                              \
            extern uint64_t SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_current_reloc;                                                  \
            extern void _skadi_subsystem_yield_stub(void);                                                                              \
            extern void (**skadi_subsystem_mtimer_sched_hook)(void);                                                                    \
            uint64_t *context_token = &SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_context_reloc;                                     \
            uint64_t *timer_reloc_token = &SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_mtimer_sched_hook_reloc;                       \
            SUBSYS_ENTRY_POINT_NAME##_context.function_ptr_impl = SUBSYS_ENTRY_POINT_NAME##_impl_wr;                                    \
            SUBSYS_ENTRY_POINT_NAME##_context.subsystem_task_id = my_task_id;                                                           \
            SUBSYS_ENTRY_POINT_NAME##_context.stack_manager = skadi_subsystem_stacks;                                                   \
            SUBSYS_ENTRY_POINT_NAME##_context.stack_manager_irq = IS_ENABLED(CONFIG_SKADI_SUBSYS_SYNC_UP) ?                             \
                skadi_subsystem_stacks_irq : NULL;                                                                                      \
            *context_token = (uint64_t) &SUBSYS_ENTRY_POINT_NAME##_context;                                                             \
            *timer_reloc_token = (uint64_t) skadi_subsystem_mtimer_sched_hook;                                                          \
            SUBSYS_ENTRY_POINT_NAME##_callee_trampoline##_skadi_subsystem_yield_stub = _skadi_subsystem_yield_stub;                     \
            SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_current_reloc = (uint64_t) &skadi_sched_current_reloc;                          \
            return true; /* OK */                                                                                                       \
        }                                                                                                                               \

#endif
#if defined(SKADI_SUBSYSTEM)
    #define SKADI_SUBSYSTEM_SETUP_CALLEE_TRAMPOLINE(SUBSYS_ENTRY_POINT_NAME)                                                        \
        SKADI_SUBSYSTEM_SETUP_CALLEE_TRAMPOLINE_NOINIT(SUBSYS_ENTRY_POINT_NAME)                                                     \
        /* we need to initialize the caller trampolines first, so we can jump into the allocator for this trampoline */             \
        static const void *const SUBSYS_ENTRY_POINT_NAME##_callee_init_fn_ptrs[] __used Z_GENERIC_SECTION(".init_array") = {        \
            SUBSYS_ENTRY_POINT_NAME##_register_init_function                                                                        \
        };
#else
    /* the init_array causes a linker error for the loader, and initialization is done explicitly in the loader anyway */
    #define SKADI_SUBSYSTEM_SETUP_CALLEE_TRAMPOLINE(SUBSYS_ENTRY_POINT_NAME) SKADI_SUBSYSTEM_SETUP_CALLEE_TRAMPOLINE_NOINIT(SUBSYS_ENTRY_POINT_NAME)
#endif

#ifdef SKADI_SUBSYSTEM_HAS_FPU
/* FPU requested */
#define SKADI_SUBSYSTEM_SET_FPU_COMMAND(SCRATCH_REG)                \
        "li "STRINGIFY(SCRATCH_REG)", "STRINGIFY(MSTATUS_FS_CLEAN)"\n\t"  \
        "csrs mstatus, "STRINGIFY(SCRATCH_REG)"\n\t"
#else
/* explicitly disable FPU if not enabled for the subsystem - using it is an error, as we do not protect FP regs on calls */
#define SKADI_SUBSYSTEM_SET_FPU_COMMAND(SCRATCH_REG)                \
        "li "STRINGIFY(SCRATCH_REG)", "STRINGIFY(MSTATUS_FS_CLEAN)"\n\t"  \
        "csrc mstatus, "STRINGIFY(SCRATCH_REG)"\n\t"
#endif


#ifdef SKADI_SUBSYSTEM_HAS_FPU
#define SKADI_SUBSYSTEM_HANDLE_CALLEE_SAVED_FPU_REGS(PREFIX, OP, SAVED_REGS_BASE)       \
        PREFIX                                                                          \
        STRINGIFY(OP) " fs0, 176("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs1, 184("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs2, 192("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs3, 200("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs4, 208("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs5, 216("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs6, 224("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs7, 232("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs8, 240("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs9, 248("STRINGIFY(SAVED_REGS_BASE)")\n\t"                     \
        STRINGIFY(OP) " fs10, 256("STRINGIFY(SAVED_REGS_BASE)")\n\t"                    \
        STRINGIFY(OP) " fs11, 264("STRINGIFY(SAVED_REGS_BASE)")\n\t"

#define SKADI_SUBSYSTEM_DESTROY_FPU_RETS                            \
        /* TODO this is an overcount if mixed int/FP-args */        \
        __asm__("fmv.d.x fa0, zero\n\t");                           \
        __asm__("fmv.d.x fa1, zero\n\t")

#if defined(CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS) || defined(CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION)

#define SKADI_SUBSYSTEM_DESTROY_FPU_REGS /* nothing to do */
#define SKADI_SUBSYSTEM_DESTROY_FPU_ARGS(ARG) /* nothing to do */
#else

#define SKADI_SUBSYSTEM_DESTROY_FPU_REGS                                    \
        __asm__(                                                            \
        "fmv.d.x fs0, zero\n\t"                                             \
        "fmv.d.x fs1, zero\n\t"                                             \
        "fmv.d.x fs2, zero\n\t"                                             \
        "fmv.d.x fs3, zero\n\t"                                             \
        "fmv.d.x fs4, zero\n\t"                                             \
        "fmv.d.x fs5, zero\n\t"                                             \
        "fmv.d.x fs6, zero\n\t"                                             \
        "fmv.d.x fs7, zero\n\t"                                             \
        "fmv.d.x fs8, zero\n\t"                                             \
        "fmv.d.x fs9, zero\n\t"                                             \
        "fmv.d.x fs10, zero\n\t"                                            \
        "fmv.d.x fs11, zero\n\t"                                            \
        "fmv.d.x ft0, zero\n\t"                                             \
        "fmv.d.x ft1, zero\n\t"                                             \
        "fmv.d.x ft2, zero\n\t"                                             \
        "fmv.d.x ft3, zero\n\t"                                             \
        "fmv.d.x ft4, zero\n\t"                                             \
        "fmv.d.x ft5, zero\n\t"                                             \
        "fmv.d.x ft6, zero\n\t"                                             \
        "fmv.d.x ft7, zero\n\t"                                             \
        "fmv.d.x ft8, zero\n\t"                                             \
        "fmv.d.x ft9, zero\n\t"                                             \
        "fmv.d.x ft10, zero\n\t"                                            \
        "fmv.d.x ft11, zero\n\t"                                            \
        );
        
#define SKADI_SUBSYSTEM_DESTROY_FPU_ARGS(NUM_ARGS)                          \
        /* TODO this is an overcount if mixed int/FP-args */                \
        if(NUM_ARGS < 1){                                                   \
            __asm__ ("fmv.d.x fa0, zero\n\t");                              \
        }                                                                   \
        if(NUM_ARGS < 2){                                                   \
            __asm__ ("fmv.d.x fa1, zero\n\t");                              \
        }                                                                   \
        if(NUM_ARGS < 3){                                                   \
            __asm__ ("fmv.d.x fa2, zero\n\t");                              \
        }                                                                   \
        if(NUM_ARGS < 4){                                                   \
            __asm__ ("fmv.d.x fa3, zero\n\t");                              \
        }                                                                   \
        if(NUM_ARGS < 5){                                                   \
            __asm__ ("fmv.d.x fa4, zero\n\t");                              \
        }                                                                   \
        if(NUM_ARGS < 6){                                                   \
            __asm__ ("fmv.d.x fa5, zero\n\t");                              \
        }                                                                   \
        if(NUM_ARGS < 7){                                                   \
            __asm__ ("fmv.d.x fa6, zero\n\t");                              \
        }                                                                   \
        if(NUM_ARGS < 8){                                                   \
            __asm__ ("fmv.d.x fa7, zero\n\t");                              \
        }

#endif /* CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS || CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION */
#else
#define SKADI_SUBSYSTEM_HANDLE_CALLEE_SAVED_FPU_REGS(PREFIX, OP, SAVED_REGS_BASE) /* nothing to do */
#define SKADI_SUBSYSTEM_DESTROY_FPU_REGS /* nothing to do */
#define SKADI_SUBSYSTEM_DESTROY_FPU_ARGS(NUM_ARGS) /* nothing to do */
#define SKADI_SUBSYSTEM_DESTROY_FPU_RETS /* nothing to do */
#endif

#if defined(NO_THREADS_IN_CALLEE_TRAMPOLINE) || !defined(CONFIG_SKADI_MARK_THREAD_IN_TRAMPOLINE)

#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_RELOCATE_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)           \
        STRINGIFY(SUBSYSTEM_ENTRY_POINT_NAME##_callee_trampoline_current_reloc)":\n\t"          \
        ".dword 0x0\n\t"

#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_MARK_CURRENT_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)

#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_RELEASE_CURRENT_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)

#else

#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_MARK_CURRENT_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)           \
        "ld t3, " STRINGIFY(SUBSYSTEM_ENTRY_POINT_NAME##_callee_trampoline_current_reloc)"\n\t"     \
        "ld t4, 0(t3)\n\t" /* t4 now has address of pointer to current thread */                    \
        "ld t5, 0(t4)\n\t" /* t5 now has address of current thread */                               \
        "sd t5, 0(sp)\n\t" /* remember the thread that this stack is associated with at TOS*/

#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_RELEASE_CURRENT_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)        \
        "sd zero, 16(sp)\n\t"


#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_RELOCATE_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)           \
        ".p2align 3\n\t"                                                                        \
        STRINGIFY(SUBSYSTEM_ENTRY_POINT_NAME##_callee_trampoline_current_reloc)":\n\t"          \
        ".dword skadi_sched_current_reloc\n\t" /* address of the address of pointer to current thread*/
#endif /* NO_THREADS_IN_CALLEE_TRAMPOLINE || !CONFIG_SKADI_MARK_THREAD_IN_TRAMPOLINE */

#ifdef CONFIG_SKADI_TEXT_ALIGN_12_BIT
/* 12-bit alignment reduces 1-cycle penalty on cva6 icache*/
#define SKADI_SUBSYSTEM_ALIGN ".p2align 12\n\t"
#else
#define SKADI_SUBSYSTEM_ALIGN ".p2align 3\n"
#endif

#ifdef CONFIG_SKADI_DEBUG
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_LOAD_STACK(SUBSYS_ENTRY_POINT_NAME)                                                                                   \
    "li t3, 128\n\t" /* dumb sanity check */                                                                                                                    \
    "bltu sp, t3, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) "_dummy_loop\n\t"                                                                    \
    "ld sp, 0(sp)\n\t" /* load stack frame into sp */                                                                                                           \
    "bltu sp, t3, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) "_dummy_loop\n\t"
#else
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_LOAD_STACK(SUBSYS_ENTRY_POINT_NAME)                                                                                   \
    "ld sp, 0(sp)\n\t"
#endif

#ifdef CONFIG_PROFILING_PERF
/* in case we encounter a profiling interrupt in the callee trampoline, need to setup frame pointer */
#define SKADI_SUBSYSTEM_CREATE_FP "addi s0, sp, 16\n\t"
#define SKADI_SUBSYSTEM_SAVE_PREVIOUS_SP \
    "sd s0, 0(sp)\n\t"                   \
    "addi s0, sp, 16\n\t"
#define SKADI_SUBSYSTEM_RESTORE_PREVIOUS_SP \
    "ld s0, 0(sp)\n\t"
#else
#define SKADI_SUBSYSTEM_CREATE_FP ""
#define SKADI_SUBSYSTEM_SAVE_PREVIOUS_SP ""
#define SKADI_SUBSYSTEM_RESTORE_PREVIOUS_SP ""
#endif

#ifdef CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS
#define SKADI_SUBSYSTEM_DESTROY_RETURNS(SUBSYS_ENTRY_POINT_NAME) ""
#elif defined(CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION)
#define SKADI_SUBSYSTEM_DESTROY_RETURNS(SUBSYS_ENTRY_POINT_NAME)        \
    "li t0, "STRINGIFY(SKADI_CLEAR_REG_CALLEE)"\n\t"                    \
    SKADI_REGCALL_STR(t0)"\n\t"

#else
#define SKADI_SUBSYSTEM_DESTROY_RETURNS(SUBSYS_ENTRY_POINT_NAME)\
    /* TODO this breaks for cases were $a1 is also a return */  \
    "li a1, 0\n\t"                                              \
    "li a2, 0\n\t"                                              \
    "li a3, 0\n\t"                                              \
    "li a4, 0\n\t"                                              \
    "li a5, 0\n\t"                                              \
    "li a6, 0\n\t"                                              \
    "li a7, 0\n\t"
#endif /* CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS */

#ifdef CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION

#define SKADI_SUBSYSTEM_CALLEE_ZERO_MASK(SUBSYS_ENTRY_POINT_NAME)   \
".p2align 3\n\t"                                                    \
STRINGIFY(SUBSYS_ENTRY_POINT_NAME) "_callee_clear_mask:\n\t"        \
".dword "STRINGIFY(SKADI_CLEAR_REG_CALLEE)"\n\t"

#else

#define SKADI_SUBSYSTEM_CALLEE_ZERO_MASK(SUBSYS_ENTRY_POINT_NAME) ""

#endif /* CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION */

#ifdef CONFIG_SKADI_SUBSYSTEM_CALL_INSTRUCTIONS
#define SKADI_SUBSYSTEM_CALL_RETURN_INSTRUCTION(ACCEPT_OWN_TASK_ID) COND_CODE_1(ACCEPT_OWN_TASK_ID, (SKADI_SRETS_STR), (SKADI_SRET_STR)) "\n\t"
#else
#define SKADI_SUBSYSTEM_CALL_RETURN_INSTRUCTION(ACCEPT_OWN_TASK_ID) "ret\n\t"
#endif


#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
#ifdef SKADI_SUBSYSTEM
extern atomic_t skadi_num_subsystem_calls;
#else
/* loader - should not interfere with the symbol, so static */

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-variable"
static atomic_t skadi_num_subsystem_calls;
#pragma GCC diagnostic pop

#endif /* SKADI_SUBSYSTEM */
#define SKADI_COUNT_SUBSYSTEM_CALL atomic_inc(&skadi_num_subsystem_calls)
#else
#define SKADI_COUNT_SUBSYSTEM_CALL
#endif /* CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS */

#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALL_ALLOC_ITERATIONS
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_RELOC(SUBSYS_ENTRY_POINT_NAME)   \
        STRINGIFY(SUBSYS_ENTRY_POINT_NAME) "_alloc_it_reloc:\n\t"                       \
        ".dword skadi_subsystem_callee_trampoline_alloc_its\n\t"

#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_ADD_PREPARE(SUBSYS_ENTRY_POINT_NAME)   \
        "li s3, 1\n\t"                                                                      \
        "ld s4, "STRINGIFY(SUBSYS_ENTRY_POINT_NAME) "_alloc_it_reloc\n\t"

#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_ADD                                \
        "ld s3, 0(s4)\n\t"                                                              \
        "addi s3, s3, 1\n\t"                                                            \
        "sd s3, 0(s4)\n\t"
#else
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_ADD                                \
        "amoadd.d zero, s3, 0(s4)\n\t"
#endif /* CONFIG_SKADI_SUBSYS_SYNC_UP */

#else
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_RELOC(SUBSYS_ENTRY_POINT_NAME)
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_ADD_PREPARE(SUBSYS_ENTRY_POINT_NAME)
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_ADD
#endif

#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
/* non-atomic access -> use IRQ disabling for synchronization of callee trampoline stack access */
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_USE_IRQ_STACK_MANAGER "li s2, 0"
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_USE_NON_IRQ_STACK_MANAGER "li s2, 8"
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_SELECT_STACK_MANAGER  \
                "add s2, t0, s2\n\t"                            \
                "ld s2, 0(s2)\n\t"

#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ALLOC_STACK(SUBSYS_ENTRY_POINT_NAME)                                                                                              \
                "ld s1, 0(s2)\n\t" /* load the bitmap normally - we are on a uniprocessor with interrupts disabled and per-IRQ-level bitmap, no concurrent execution */     \
                "beqz s1, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_check_stack_frame_occupied\n\t" /* all 0 - no stacks available, try agin */             \
                "ctz t2, s1\n\t" /* t2 is trailing zeros, i.e., the first free register set */                                                                              \
                "bclr s1, s1, t2\n\t" /* clear the register set - this is ours now! */                                                                                      \
                "sd s1, 0(s2)\n\t" /* store back - no concurrent modification possible! */

#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_CLEAR_STACK_MASK \
        "ld s3, 0(s2)\n\t"                                 \
        "or s1, s1, s3\n\t"                                \
        "sd s1, 0(s2)\n\t"

#else
/* atomic access -> use atomic instructions for synchronization of callee trampoline stack access */
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_USE_IRQ_STACK_MANAGER ""
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_USE_NON_IRQ_STACK_MANAGER ""
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_SELECT_STACK_MANAGER "ld s2, 8(t0)\n\t" /* load pointer to non-irq stack manager into s2 */
#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ALLOC_STACK(SUBSYS_ENTRY_POINT_NAME)                                                                                              \
                "lr.d s1, 0(s2)\n\t" /* load the bitmap with a reservation - can be used to later check if someone modified concurrently */                                 \
                "beqz s1, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_check_stack_frame_occupied\n\t" /* all 0 - no stacks available, try agin */             \
                "ctz t2, s1\n\t" /* t2 is trailing zeros, i.e., the first free register set */                                                                              \
                "bclr s1, s1, t2\n\t" /* clear the register set - this is ours now! */                                                                                      \
                "sc.d s1, s1, 0(s2)\n\t" /* store back - can check if anyone has modified in the meantime */                                                                \
                "bnez s1, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_check_stack_frame_occupied\n\t" /* was modified - try again */

#define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_CLEAR_STACK_MASK "amoor.d zero, s1, 0(s2)\n\t" /* remove occupied atomically, preventing races (works because occupied flag is not removed) */
#endif

/**
 * Conditionally destroy integer and FPU return addresses
 * Condition: passed type (return type) is void; destruction of FPU return registers also depends on FPU use in the submodule.
 * Implementation: C11 _Generic statement, matching pointer-to-return value (void*, something-else-*) -> if void*: destroy return registers, otherwise: let them live
 * Hacks: _Generic accepts an expression, not a statement, so the statement I want is wrapped into a block that returns 0 (which is discarded)
 * 
 */
#define SKADI_SUBSYSTEM_CLEAR_RET_VOID(t) _Generic((t*)0, void* : ({__asm__ volatile("li a0, 0\n\tli a1,0"); SKADI_SUBSYSTEM_DESTROY_FPU_RETS; 0;}), default: ({__asm__ volatile(""); 0;}))

    /**
     * @brief Body of the SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE macros, with code to restore / reset IRQ as extra parameter
     */
    #define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ_DECL(RESTORE_IRQ_COMMAND, IS_IRQ, ACCEPT_OWN_TASK_ID, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)    \
        extern SUBSYS_ENTRY_POINT_RETVAL SUBSYS_ENTRY_POINT_NAME##_callee_trampoline ( __VA_ARGS__ );                                                                       \
        extern void SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_end (void);                                                                                                 \
        EXPORT_SYMBOL(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline); /* so the loader finds it */                                                                            \
        EXPORT_SYMBOL(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_end); /* so the loader finds its end */                                                                   \
        /* for getting function pointer, set by the loader; can be used in scenarios where pointer type matters */                                                          \
        SUBSYS_ENTRY_POINT_RETVAL (*SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_function_pointer)(__VA_ARGS__)                                                              \
            = (__typeof(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_function_pointer))0xdead;                                                                               \
        /* so the loader finds the function ptr */                                                                                                                          \
        EXPORT_SYMBOL(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_function_pointer);                                                                                        \
        static inline void check_return_address_##SUBSYS_ENTRY_POINT_NAME (uint64_t return_capability,                                                                      \
                                                                    const struct skadi_subsystem_context *skadi_ctx){                                                       \
            const char *reason;                                                                                                                                             \
            if(return_capability == 0){                                                                                                                                     \
                SKADI_SUBSYSTEM_ERROR("Subsystem entry point %s cannot accept return capability %p!", STRINGIFY(SUBSYS_ENTRY_POINT_NAME),                                   \
                           (void*)(uintptr_t)return_capability);                                                                                                            \
                csr_clear(mstatus, 0x8);                                                                                                                                    \
                for(;;){}                                                                                                                                                   \
            }                                                                                                                                                               \
            if(!skadi_subsystem_can_accept_function_pointer(return_capability,&reason,skadi_ctx->subsystem_task_id, IS_IRQ, ACCEPT_OWN_TASK_ID)){                           \
                SKADI_SUBSYSTEM_ERROR("Subsystem entry point %s cannot accept return capability %p: %s\n",                                                                  \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME), (void*)(uintptr_t)return_capability, reason);                                                                           \
                csr_clear(mstatus, 0x8);                                                                                                                                    \
                for(;;){}                                                                                                                                                   \
                k_panic();                                                                                                                                                  \
            }                                                                                                                                                               \
        }                                                                                                                                                                   \
                                                                                                                                                                            \
        __asm__(".global " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) "\n"                                                                                      \
                /* sets the type of the symbol in the output ELF, making it recognizable to init_order */                                                                   \
                ".type " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) ",%function\n"                                                                              \
                SKADI_SUBSYSTEM_ALIGN                                                                                                                                       \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) ":\n\t"                                                                                              \
                /* we cannot accept interrupts right now, as we are not fully set up */                                                                                     \
                /* we also need to keep the old value of the CSR, such that we do not accidentally enable IRQs */                                                           \
                "csrrci s5, mstatus, " STRINGIFY(MSTATUS_MIE) "\n\t"                                                                                                        \
                SKADI_SUBSYSTEM_FLUSH_CACHES /* prevent microarchitectural leaks */                                                                                         \
                SKADI_SUBSYSTEM_FLUSH_BRANCH_TARGET_PREDICTION                                                                                                              \
                "li s3, 0x1\n\t"                                                                                                                                            \
                "slli s3, s3, " STRINGIFY(SKADI_NONSTANDARD_MSTATUS_ISR_SHIFT) "\n\t"                                                                                       \
                "and s3, s3, s5\n\t"                                                                                                                                        \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_USE_IRQ_STACK_MANAGER "\n\t" /* assume IRQ stack manager - will fix soon-ish */                                           \
                "bnez s3, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) "_yield_stub_set\n\t" /* in ISR - sched hook is not writable (and not used!) */          \
                "ld t1, "STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_skadi_subsystem_yield_stub\n\t"                                                            \
                "csrw "STRINGIFY(SKADI_MTIMER_HOOK_CSR) ", t1\n\t"  /* sched hook HAS to be set via CSR - otherwise, loader / untrusted ISR handler could manipulate */     \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_USE_NON_IRQ_STACK_MANAGER "\n\t" /* non-IRQ stack manager */                                                              \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) "_yield_stub_set:\n\t"                                                                               \
                /* We first need to restore our context capability. */                                                                                                      \
                /* We load it into the t0 register using only immediate loads. */                                                                                           \
                /* We will patch these instructions such that the actual token is restored when creating */                                                                 \
                /* the X-only capability. */                                                                                                                                \
                /* load the context pointer */                                                                                                                              \
                "ld t0, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_context_reloc\n\t"                                                                        \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_SELECT_STACK_MANAGER "\n\t"                                                                                               \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_ADD_PREPARE(SUBSYS_ENTRY_POINT_NAME)                                                                           \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_check_stack_frame_occupied:\n\t"                                                                    \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_ADD                                                                                                            \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ALLOC_STACK(SUBSYS_ENTRY_POINT_NAME) "\n\t"                                                                               \
                "li s1, 1\n\t" /* prepare restore mask */                                                                                                                   \
                "sll s1, s1, t2\n\t" /* s1 is our restore mask now */                                                                                                       \
                "slli t2, t2, 3\n\t" /* calculate offset for stack */                                                                                                       \
                "addi t2, t2, 8\n\t" /* skip bitmap at beginning */                                                                                                         \
                "add sp, t2, s2\n\t" /* load address of stack frame into sp*/                                                                                               \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_LOAD_STACK (SUBSYS_ENTRY_POINT_NAME)                                                                                      \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_MARK_CURRENT_THREAD (SUBSYS_ENTRY_POINT_NAME) /* such that we can free it if thread is cancelled */                       \
                /* we have registered the interrupt handler and restored sp - restore interrupt settings if desired by our wrapper macro */                                 \
                SKADI_SUBSYSTEM_SET_FPU_COMMAND (t3)                                                                                                                        \
                "addi sp, sp, -16\n\t"         /* Allocate space for return address on stack, keeping alignment */                                                          \
                SKADI_SUBSYSTEM_SAVE_PREVIOUS_SP                                                                                                                            \
                "sd ra, 8(sp)\n\t"               /* Save return address */                                                                                                  \
                SKADI_SUBSYSTEM_CREATE_FP                                                                                                                                   \
                RESTORE_IRQ_COMMAND                                                                                                                                         \
                "csrw mie, t5\n\t"  /* immediate field is too small for value*/                                                                                             \
                "csrsi mstatus, "STRINGIFY(MSTATUS_MIE)"\n\t"                                                                                                               \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_irq_restored)":\n\t"                                                                                                    \
                "mv t3, ra\n\t"               /* Copy return address for checking */                                                                                        \
                /* TODO: other registers such as function / thread pointer etc. */                                                                                          \
                "ld t1,16(t0)\n\t" /* load address of the C function that implements the subsystem */                                                                        \
                "jalr ra, 0(t1)\n\t" /* jump into C function, relying on JALR to also setup return address */                                                               \
                "ld ra, 8(sp)\n\t"            /* Restore return address */                                                                                                  \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_RELEASE_CURRENT_THREAD(SUBSYS_ENTRY_POINT_NAME) /* stack no longer associated with this thread */                         \
                "csrci mstatus, " STRINGIFY(MSTATUS_MIE) "\n\t" /* disable timer interrupts - stack about to become invalid */                                              \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_CLEAR_STACK_MASK "\n\t"                                                                                                   \
                SKADI_SUBSYSTEM_DESTROY_REGISTERS                                                                                                                           \
                SKADI_SUBSYSTEM_DESTROY_RETURNS(SUBSYS_ENTRY_POINT_NAME)                                                                                                    \
                /* get rid of floating-point regs to prevent leaks, known to return in fa0, fa1 at all times (same restriction as above for void though) */                 \
    );                                                                                                                                                                      \
                SKADI_SUBSYSTEM_DESTROY_FPU_REGS;                                                                                                                           \
    __asm__(                                                                                                                                                                \
                SKADI_SUBSYSTEM_FLUSH_CACHES /* prevent microarchitectural leaks */                                                                                         \
                SKADI_SUBSYSTEM_FLUSH_BRANCH_TARGET_PREDICTION                                                                                                              \
                SKADI_SUBSYSTEM_CALL_RETURN_INSTRUCTION(ACCEPT_OWN_TASK_ID)                                                                                                 \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) "_dummy_loop:\n\t"                                                                                   \
                "j "STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) "_dummy_loop\n"                                                                                  \
                /* token needs 8-byte alignment for ld */                                                                                                                   \
                ".p2align 3\n"                                                                                                                                              \
                /* token for C function as well as padding for speculative fetching of next instruction */                                                                  \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_context_reloc:\n\t"                                                                                 \
                ".dword 0x0\n"                                                                                                                                              \
                ".p2align 3\n"                                                                                                                                              \
                /* token for  skadi_subsystem_mtimer_sched_hook, used to install timer ISR*/                                                                                \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_mtimer_sched_hook_reloc:\n\t"                                                                       \
                ".dword 0x0\n"                                                                                                                                              \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_skadi_subsystem_yield_stub:\n\t"                                                                    \
                ".dword 0x0\n"                                                                                                                                              \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_RELOCATE_THREAD(SUBSYS_ENTRY_POINT_NAME)                                                                                  \
                SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ITERATIONS_RELOC(SUBSYS_ENTRY_POINT_NAME)                                                                               \
                SKADI_SUBSYSTEM_CALLEE_ZERO_MASK(SUBSYS_ENTRY_POINT_NAME)                                                                                                   \
                ".global " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_end) "\n"                                                                                  \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_end) ":\n\t"                                                                                          \
                "ebreak\n" /* should never be reached */                                                                                                                    \
                /* generates size information for the symbol; needed to be recognized as exported in init_order */                                                          \
                ".size " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) ",.-"                                                                                       \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)                                                                                                      \
        );

#if defined(CONFIG_SKADI_SUBSYSTEM_CALL_NOCHECKS) || defined(CONFIG_SKADI_SUBSYSTEM_CALL_INSTRUCTIONS)
        #define SKADI_SUBSYSTEM_CALLEE_RETURN_CHECK(SUBSYS_ENTRY_POINT_NAME) /* nothing to do */
#else
        #define SKADI_SUBSYSTEM_CALLEE_RETURN_CHECK(SUBSYS_ENTRY_POINT_NAME) check_return_address_##SUBSYS_ENTRY_POINT_NAME(return_capability,context)
#endif

    #define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ(RESTORE_IRQ_COMMAND, IS_IRQ, ACCEPT_OWN_TASK_ID, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)         \
        SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ_DECL(RESTORE_IRQ_COMMAND, IS_IRQ, ACCEPT_OWN_TASK_ID, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, __VA_ARGS__)\
        SUBSYS_ENTRY_POINT_RETVAL SUBSYS_ENTRY_POINT_NAME ## _impl ( __VA_ARGS__ );                                                                                         \
        SUBSYS_ENTRY_POINT_RETVAL __attribute__((naked)) SUBSYS_ENTRY_POINT_NAME ## _impl_wr (__VA_ARGS__){                                                                 \
            /* thin wrapper function - only purpose is to destroy return address for voids */                                                                               \
            __asm__ volatile(                                                                                                                                               \
                "mv s11, ra\n\t" /* need the return address for later */                                                                                                    \
                "ld t1, "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_wrapper_real_function\n\t"                                                                                     \
                "jalr ra, 0(t1)\n\t" /* do the actual call */                                                                                                               \
            );                                                                                                                                                              \
            SKADI_SUBSYSTEM_CLEAR_RET_VOID(SUBSYS_ENTRY_POINT_RETVAL); /* the purpose the function exists - clear return value for void! */                                 \
            __asm__ volatile(                                                                                                                                               \
                "jr s11\n\t"/* return */                                                                                                                                    \
                ".p2align 3\n"                                                                                                                                              \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_wrapper_real_function:\n\t"                                                                                             \
                ".dword " STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_impl\n\t"                                                                                                     \
            );                                                                                                                                                              \
        }                                                                                                                                                                   \
        SUBSYS_ENTRY_POINT_RETVAL SUBSYS_ENTRY_POINT_NAME ## _impl ( __VA_ARGS__ ){                                                                                         \
            struct skadi_subsystem_context *context;                                                                                                                        \
            uint64_t return_capability;                                                                                                                                     \
            __asm__ volatile (                                                                                                                                              \
                "mv %0, t0"                                                                                                                                                 \
                : "=r" (context)                                                                                                                                            \
            );                                                                                                                                                              \
            __asm__ volatile (                                                                                                                                              \
                "mv %0, t3"                                                                                                                                                 \
                : "=r" (return_capability)                                                                                                                                  \
            );                                                                                                                                                              \
            SKADI_COUNT_SUBSYSTEM_CALL;                                                                                                                                     \
            SKADI_SUBSYSTEM_CALLEE_RETURN_CHECK(SUBSYS_ENTRY_POINT_NAME);                  
    
    #define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ_VARIADIC(RESTORE_IRQ_COMMAND, IS_IRQ, ACCEPT_OWN_TASK_ID, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)\
        SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ_DECL(RESTORE_IRQ_COMMAND, IS_IRQ, ACCEPT_OWN_TASK_ID, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, __VA_ARGS__)\
        SUBSYS_ENTRY_POINT_RETVAL SUBSYS_ENTRY_POINT_NAME ## _impl ( __VA_ARGS__, ... );                                                                                    \
        SUBSYS_ENTRY_POINT_RETVAL __attribute__((naked)) SUBSYS_ENTRY_POINT_NAME ## _impl_wr (__VA_ARGS__, ...){                                                            \
            /* thin wrapper function - only purpose is to destroy return address for voids */                                                                               \
            __asm__ volatile(                                                                                                                                               \
                "mv s11, ra\n\t" /* need the return address for later */                                                                                                    \
                "ld t0, "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_wrapper_real_function\n\t"                                                                                     \
                "jalr ra, 0(t0)\n\t" /* do the actual call */                                                                                                               \
            );                                                                                                                                                              \
            SKADI_SUBSYSTEM_CLEAR_RET_VOID(SUBSYS_ENTRY_POINT_RETVAL); /* the purpose the function exists - clear return value for void! */                                 \
            __asm__ volatile(                                                                                                                                               \
                "jr s11\n\t"/* return */                                                                                                                                    \
                ".p2align 3\n"                                                                                                                                              \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_wrapper_real_function:\n\t"                                                                                             \
                ".dword " STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_impl\n\t"                                                                                                     \
            );                                                                                                                                                              \
        }                                                                                                                                                                   \
        SUBSYS_ENTRY_POINT_RETVAL SUBSYS_ENTRY_POINT_NAME ## _impl ( __VA_ARGS__ , ... ){                                                                                   \
            struct skadi_subsystem_context *context;                                                                                                                        \
            uint64_t return_capability;                                                                                                                                     \
            __asm__ volatile (                                                                                                                                              \
                "mv %0, t0"                                                                                                                                                 \
                : "=r" (context)                                                                                                                                            \
            );                                                                                                                                                              \
            __asm__ volatile (                                                                                                                                              \
                "mv %0, t3"                                                                                                                                                 \
                : "=r" (return_capability)                                                                                                                                  \
            );                                                                                                                                                              \
            SKADI_COUNT_SUBSYSTEM_CALL;                                                                                                                                     \
            SKADI_SUBSYSTEM_CALLEE_RETURN_CHECK(SUBSYS_ENTRY_POINT_NAME);                  
    
    /**
     * @brief Interrupts allowed during Skadi subsystem call: external, timer, software
     */
    #define SKADI_SUBSYSTEM_ALL_IRQ_MASK ((1<<IRQ_M_EXT) | (1<<IRQ_M_TIMER) | (1<<IRQ_M_SOFT))

    
    #define SKADI_SUBSYSTEM_NO_TIMER_MASK ((1<<IRQ_M_EXT) | (1<<IRQ_M_SOFT))

    #define SKADI_SUBSYSTEM_ALLOW_ALL_IRQ \
        "li t5, "STRINGIFY(SKADI_SUBSYSTEM_ALL_IRQ_MASK)"\n\t"
/* TODO IRQs currently not handled */
    #define SKADI_SUBSYSTEM_ALLOW_DEVICE_IRQ_IF_NOT_ATOMIC(SUBSYS_ENTRY_POINT_NAME) \
        "li t5, "STRINGIFY(SKADI_SUBSYSTEM_NO_TIMER_MASK)"\n\t"                     \
        "bnez s3," STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_irq_restored)"\n\t"

    /**
     * Defines a subsystem entry point. Unconditionally enables interrupts during execution of the subsystem call.
     * Mandatory arguments: return value and name
     * Exemplary use:
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, foobar, int arg1, int arg2, int arg3, ...){
     *  do_something();
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(foobar)
     */
    #define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)                          \
        SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ(SKADI_SUBSYSTEM_ALLOW_ALL_IRQ,                                            \
                                                           false,                                                               \
                                                           false,                                                               \
                                                           SUBSYS_ENTRY_POINT_RETVAL,                                           \
                                                           SUBSYS_ENTRY_POINT_NAME,                                             \
                                                           __VA_ARGS__)

    /**
     * Defines a subsystem entry point. Unconditionally enables interrupts during execution of the subsystem call.
     * Mandatory arguments: return value and name
     * Exemplary use:
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_VARIADIC(int, foobar, int arg1, int arg2, int arg3){
     *  // declaration: int foobar(int arg1, int arg2, int arg3, ...)
     *  va_list args;
     *  //...
     *  va_start(args, arg3);
     *  int bar = va_arg(args, int); // ...
     *  va_end(args);
     *  do_something();
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(foobar)
     */
    #define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_VARIADIC(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)                 \
        SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ_VARIADIC(SKADI_SUBSYSTEM_ALLOW_ALL_IRQ,                                   \
                                                           false,                                                               \
                                                           false,                                                               \
                                                           SUBSYS_ENTRY_POINT_RETVAL,                                           \
                                                           SUBSYS_ENTRY_POINT_NAME,                                             \
                                                           __VA_ARGS__)

    /**
     * Defines a subsystem entry point that is to be executed with interrupts disabled.
     * Mandatory arguments: return value and name
     * Exemplary use:
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, foobar, int arg1, int arg2, int arg3, ...){
     *  do_something();
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(foobar)
     */
    #define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)                    \
        SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ(SKADI_SUBSYSTEM_ALLOW_DEVICE_IRQ_IF_NOT_ATOMIC(SUBSYS_ENTRY_POINT_NAME),  \
                                                      true,                                                                     \
                                                      false,                                                                    \
                                                      SUBSYS_ENTRY_POINT_RETVAL,                                                \
                                                      SUBSYS_ENTRY_POINT_NAME,                                                  \
                                                      __VA_ARGS__)
    /**
     * Defines a subsystem entry point that is to be executed with interrupts disabled and allows a return capability with set-task-ID restriction to our own task ID.
     * Mandatory arguments: return value and name
     * Exemplary use:
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ_ALLOW_SELF(int, foobar, int arg1, int arg2, int arg3, ...){
     *  do_something();
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(foobar)
     */
    #define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)                 \
        SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ(SKADI_SUBSYSTEM_ALLOW_DEVICE_IRQ_IF_NOT_ATOMIC(SUBSYS_ENTRY_POINT_NAME),          \
                                                           true,                                                                        \
                                                           true,                                                                        \
                                                           SUBSYS_ENTRY_POINT_RETVAL,                                                   \
                                                           SUBSYS_ENTRY_POINT_NAME,                                                     \
                                                           __VA_ARGS__)
    
    /**
     * Defines a subsystem entry point that is to be executed with interrupts enabled and allows a return capability with set-task-ID restriction to our own task ID.
     * Mandatory arguments: return value and name
     * Exemplary use:
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ALLOW_SELF(int, foobar, int arg1, int arg2, int arg3, ...){
     *  do_something();
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(foobar)
     */
    #define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)                   \
         SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ(SKADI_SUBSYSTEM_ALLOW_ALL_IRQ,                                               \
                                                           false,                                                                   \
                                                           true,                                                                    \
                                                           SUBSYS_ENTRY_POINT_RETVAL,                                               \
                                                           SUBSYS_ENTRY_POINT_NAME,                                                 \
                                                           __VA_ARGS__)

    /**
     * Defines a subsystem entry point for the main function with arguments.
     * Exemplary use:
     * SKADI_SUBSYSTEM_MAIN (int argc, char **argv) {
     *  do_something();
     * SKADI_SUBSYSTEM_MAIN_END
     */
    #define SKADI_SUBSYSTEM_MAIN(...)                                                                                           \
        SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ(SKADI_SUBSYSTEM_ALLOW_ALL_IRQ,                                            \
                                                           false,                                                               \
                                                           false,                                                               \
                                                           int,                                                                 \
                                                           main,                                                                \
                                                           __VA_ARGS__)
    
                                                           /**
     * Defines a subsystem entry point for the main function with arguments.
     * Main is not interrupted by timer interrupts.
     * Exemplary use:
     * SKADI_SUBSYSTEM_MAIN_NOIRQ (int argc, char **argv) {
     *  do_something();
     * SKADI_SUBSYSTEM_MAIN_END
     */
    #define SKADI_SUBSYSTEM_MAIN_NOIRQ(...)                                                                                     \
        SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_WITHOUT_IRQ(SKADI_SUBSYSTEM_ALLOW_DEVICE_IRQ_IF_NOT_ATOMIC(main),                     \
                                                           true,                                                                \
                                                           false,                                                               \
                                                           int,                                                                 \
                                                           main,                                                                \
                                                           __VA_ARGS__)

    #define SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(SUBSYS_ENTRY_POINT_NAME)                                          \
    }                                                                                                               \
    /* creates init function for the callee trampoline */                                                           \
    SKADI_SUBSYSTEM_SETUP_CALLEE_TRAMPOLINE(SUBSYS_ENTRY_POINT_NAME)                                                \

    #define SKADI_SUBSYSTEM_MAIN_END SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(main)

    #define SKADI_SUBSYSTEM_FUNCTION_POINTER(SUBSYS_ENTRY_POINT_NAME) SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_function_pointer

    

    /**
     * Registers that the caller needs to safe from being overwritten.
     */
    struct skadi_subsystem_caller_register_set {
        uint64_t sp;
        uint64_t gp;
        uint64_t tp;
        uint64_t fp;
        uint64_t s1;
        uint64_t s2;
        uint64_t s3;
        uint64_t s4;
        uint64_t s5;
        uint64_t s6;
        uint64_t s7;
        uint64_t s8;
        uint64_t s9;
        uint64_t s10;
        uint64_t s11;
        uint64_t ra;
        /* need to save/restore IRQ state before call, as might be changed by callee */
        uint64_t mstatus;
        uint64_t mie;
        /* used to check (atomically) that this was not used */
        uint64_t reserved_mutex;
        /* mask that we can use to free this register set again in the bitmap */
        uint64_t free_mask;
        /* pointer to the trampoline wrapper where the bitmap is located */
        uint64_t caller_trampoline_wrapper;
        /* thread that this call associated with - for cleaning caller trampoline in case thread is killed */
        struct k_thread *associated_thread;
#ifdef SKADI_SUBSYSTEM_HAS_FPU
        /* callee-saved FP regs */
        double fs0;
        double fs1;
        double fs2;
        double fs3;
        double fs4;
        double fs5;
        double fs6;
        double fs7;
        double fs8;
        double fs9;
        double fs10;
        double fs11;
        double fs12;
#endif
    };

    /**
     * "Return address" of the caller
     */
    struct skadi_subsystem_caller_trampoline {
        // the return address will point here
        uint32_t return_trampoline[6];
        // where the wrapper function continues
        uint64_t epilogue;
        // saved registers
        // separate, because the trampoline needs to be readable
        // registers can be task-restricted
        struct skadi_subsystem_caller_register_set *registers;
        // set-task-id return capability
        void *return_addr;
    } __attribute__((__packed__));

    struct skadi_subsystem_caller_trampoline_wrapper{
        // bitmap for which trampolines are in use
        uint64_t bitmap;
        // pointers to actual trampolines
        struct skadi_subsystem_caller_trampoline *trampolines[CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS];
        // bitmap for which trampolines are in use
        uint64_t bitmap_irq;
        // pointers to actual trampolines
        struct skadi_subsystem_caller_trampoline *trampolines_irq[CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ];
    };

    extern struct skadi_subsystem_caller_trampoline_wrapper skadi_subsystem_caller_trampoline;
    
#ifdef CONFIG_SKADI_TEXT_ALIGN_12_BIT
    #define SKADI_CALLER_TRAMPOLINE_ALIGNMENT 12
#else
    #define SKADI_CALLER_TRAMPOLINE_ALIGNMENT 0
#endif

#define SKADI_CALLER_TRAMPOLINE_RESTRICTION SKADI_TASK_ID_BOUND_RESTRICTION(task_id, SKADI_DEVICE_ID_CPU)

#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
    #define SKADI_SUBSYSTEM_DECLARE_CALLER_TRAMPOLINES_IRQ(SUBSYS_ENTRY_POINT_NAME)                                                                         \
        for(int i = 0; i < CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ; i++){                                                            \
                const skadi_restriction_t restriction = SKADI_TASK_ID_RESTRICTION(task_id, SKADI_DEVICE_ID_CPU, SKADI_RESTRICTIONS_SET_TASK_ID);            \
                const skadi_restriction_t restriction_writable = SKADI_CALLER_TRAMPOLINE_RESTRICTION;                                                       \
                struct skadi_subsystem_caller_trampoline *trampoline = __skadi__##SUBSYS_ENTRY_POINT_NAME##_caller_trampolines_irq[i];                      \
                /* we need a writable token to be able to copy the actual return address in */                                                              \
                return_addr_ok = skadi_cap_ops_derive(trampoline, restriction_writable,                                                                     \
                                                        sizeof(struct skadi_subsystem_caller_trampoline),                                                   \
                                                        skadi_get_capability_offset(trampoline),                                                            \
                                                        SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE                    \
                                                        | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,                               \
                                                        &derived_cap_writable);                                                                             \
                return_addr_ok &= skadi_cap_ops_derive_min_cap_type(trampoline, restriction,                                                                \
                                                        sizeof(struct skadi_subsystem_caller_trampoline),                                                   \
                                                        skadi_get_capability_offset(trampoline),                                                            \
                                                        SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_IRQ_ACCESSIBLE                  \
                                                        | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,                               \
                                                        IS_ENABLED(CONFIG_SKADI_TEXT_ALIGN_12_BIT) ? SKADI_CAPABILITY_TYPE_OFFSET_16_BIT :                  \
                                                        SKADI_CAPABILITY_TYPE_OFFSET_8_BIT, &derived_cap);                                                  \
                                                                                                                                                            \
_Pragma("GCC diagnostic push")                                                                                                                              \
_Pragma("GCC diagnostic ignored \"-Warray-bounds=\"")                                                                                                       \
_Pragma("GCC diagnostic ignored \"-Wstringop-overflow=\"")                                                                                                  \
                memcpy(trampoline->return_trampoline,SUBSYS_ENTRY_POINT_NAME##_trampoline_code,trampoline_code_len);                                        \
                __asm__ volatile("fence.i"); /* make sure the data are visible to the instruction cache */                                                  \
_Pragma("GCC diagnostic pop")                                                                                                                               \
                if(!return_addr_ok || !derived_cap || sizeof(struct skadi_subsystem_caller_trampoline) + sizeof(uintptr_t) <= trampoline_code_len){         \
                    SKADI_SUBSYSTEM_ERROR("Could not derive return capability!\n");                                                                         \
                    return false;                                                                                                                           \
                }                                                                                                                                           \
                else{                                                                                                                                       \
                    SKADI_SUBSYSTEM_DEBUG("Got caller trampoline addr 0x%"PRIx64" for subsystem call "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"\n",               \
                                          (uint64_t) derived_cap);                                                                                          \
                }                                                                                                                                           \
                                                                                                                                                            \
                trampoline->registers = &SUBSYS_ENTRY_POINT_NAME##_caller_saved_register_array_irq[i];                                                      \
                                                                                                                                                            \
                trampoline->return_addr = derived_cap;                                                                                                      \
                SUBSYS_ENTRY_POINT_NAME##_caller_trampoline.trampolines_irq[i] = (void *) derived_cap_writable; /* writable permission will persist */      \
                return_addr_ok &= skadi_cap_ops_restrict(trampoline, restriction_writable, 0, 0, 0); /* only used derived cap's from now on */              \
                if(!return_addr_ok){                                                                                                                        \
                    return false;                                                                                                                           \
                }                                                                                                                                           \
            }
#else
            #define SKADI_SUBSYSTEM_DECLARE_CALLER_TRAMPOLINES_IRQ(SUBSYS_ENTRY_POINT_NAME)                                     \
            ARG_UNUSED(skadi_subsystem_caller_saved_register_array_irq);
#endif

    #define SKADI_SUBSYSTEM_DECLARE_CALLER_TRAMPOLINE(SUBSYS_ENTRY_POINT_NAME)                                                                              \
        extern struct skadi_subsystem_caller_trampoline *__skadi__##SUBSYS_ENTRY_POINT_NAME##_caller_trampolines                                            \
                                                    [CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS]; /* provided by loader - init cycle */     \
        extern struct skadi_subsystem_caller_trampoline *__skadi__##SUBSYS_ENTRY_POINT_NAME##_caller_trampolines_irq                                        \
                                                    [CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ]; /* provided by loader - init cycle */ \
        static struct skadi_subsystem_caller_register_set                                                                                                   \
            SUBSYS_ENTRY_POINT_NAME##_caller_saved_register_array[CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS] = {0};                        \
        static struct skadi_subsystem_caller_register_set                                                                                                   \
            SUBSYS_ENTRY_POINT_NAME##_caller_saved_register_array_irq[CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ] = {0};                \
        /* we need the trampoline to live in a text section, otherwise, it goes to data and is allocated in a non-executable section */                     \
        /* the following hack places the trampoline in a custom section and overwrites the auto-generated flags, which again would make it data */          \
        /* originally from https://stackoverflow.com/a/3454066 */                                                                                           \
        static struct skadi_subsystem_caller_trampoline __attribute__((used))                                                                               \
                                                            __attribute__((section(".text.skadi.trampolines."                                               \
                                                                                   STRINGIFY(SUBSYS_ENTRY_POINT_NAME)                                       \
                                                                                   ",\"ax\",@progbits #")))                                                 \
                                                            SUBSYS_ENTRY_POINT_NAME##_trampolines                                                           \
                                                            [CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS];                                   \
        struct skadi_subsystem_caller_trampoline_wrapper __attribute__((used)) SUBSYS_ENTRY_POINT_NAME##_caller_trampoline =                                \
            {.bitmap = ((1<<CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS)-1),                                                                 \
             .bitmap_irq = ((1<<CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ)-1)}; /* same thing for IRQ */                               \
        extern void SUBSYS_ENTRY_POINT_NAME##_trampoline_code(void);                                                                                        \
        extern void SUBSYS_ENTRY_POINT_NAME##_trampoline_code_end(void);                                                                                    \
        __asm__(                                                                                                                                            \
            SKADI_SUBSYSTEM_ALIGN                                                                                                                           \
            STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_trampoline_code) ":\n\t"                                                                                    \
            /* we are unable to take interrupts now, as we are not fully set up */                                                                          \
            /* no need to maintain the old value - will read it alongside mie from saved registers */                                                       \
            "csrci mstatus, " STRINGIFY(MSTATUS_MIE) "\n\t"                                                                                                 \
            "auipc t0,0\n\t" /* figure out where we are; t0 now holds the beginning of the struct*/                                                         \
            "ld t1, 20(t0)\n\t" /* get the next actual code address from the struct */                                                                      \
            SKADI_SUBSYSTEM_FLUSH_BRANCH_TARGET_PREDICTION /* prevent spurious subsystem calls in branch target prediction */                               \
            "jr t1\n\t" /* jump to the remainder of the function */                                                                                         \
            "c.ebreak\n\t" /* padding to 24 bytes, as trampoline is 24 bytes long */                                                                        \
            STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_trampoline_code_end) ":\n\t"                                                                                \
            "nop\n"                                                                                                                                         \
        );                                                                                                                                                  \
                                                                                                                                                            \
        bool SUBSYS_ENTRY_POINT_NAME##_setup_return_addr(void){                                                                                             \
            skadi_task_id_t task_id = SKADI_CURRENT_TASK_ID;                                                                                                \
            bool return_addr_ok;                                                                                                                            \
            void* derived_cap=0, *derived_cap_writable=0;                                                                                                   \
            uintptr_t end_ptr = (uintptr_t)SUBSYS_ENTRY_POINT_NAME##_trampoline_code_end;                                                                   \
            uintptr_t start_ptr = (uintptr_t)SUBSYS_ENTRY_POINT_NAME##_trampoline_code;                                                                     \
            const size_t trampoline_code_len = end_ptr - start_ptr;                                                                                         \
            for(int i = 0; i < CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS; i++){                                                            \
                const skadi_restriction_t restriction = SKADI_TASK_ID_RESTRICTION(task_id, SKADI_DEVICE_ID_CPU, SKADI_RESTRICTIONS_SET_TASK_ID);            \
                const skadi_restriction_t restriction_writable = SKADI_CALLER_TRAMPOLINE_RESTRICTION;                                                       \
                struct skadi_subsystem_caller_trampoline *trampoline = __skadi__##SUBSYS_ENTRY_POINT_NAME##_caller_trampolines[i];                          \
                /* we need a writable token to be able to copy the actual return address in */                                                              \
                return_addr_ok = skadi_cap_ops_derive(trampoline, restriction_writable,                                                                     \
                                                        sizeof(struct skadi_subsystem_caller_trampoline),                                                   \
                                                        skadi_get_capability_offset(trampoline),                                                            \
                                                        SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE                    \
                                                        | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,                               \
                                                        &derived_cap_writable);                                                                             \
                return_addr_ok &= skadi_cap_ops_derive_min_cap_type(trampoline, restriction,                                                                \
                                                        sizeof(struct skadi_subsystem_caller_trampoline),                                                   \
                                                        skadi_get_capability_offset(trampoline),                                                            \
                                                        SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_IRQ_ACCESSIBLE                  \
                                                        | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,                               \
                                                        IS_ENABLED(CONFIG_SKADI_TEXT_ALIGN_12_BIT) ? SKADI_CAPABILITY_TYPE_OFFSET_16_BIT :                  \
                                                        SKADI_CAPABILITY_TYPE_OFFSET_8_BIT, &derived_cap);                                                  \
                                                                                                                                                            \
_Pragma("GCC diagnostic push")                                                                                                                              \
_Pragma("GCC diagnostic ignored \"-Warray-bounds=\"")                                                                                                       \
_Pragma("GCC diagnostic ignored \"-Wstringop-overflow=\"")                                                                                                  \
                memcpy(trampoline->return_trampoline,SUBSYS_ENTRY_POINT_NAME##_trampoline_code,trampoline_code_len);                                        \
                __asm__ volatile("fence.i"); /* make sure the data are visible to the instruction cache */                                                  \
_Pragma("GCC diagnostic pop")                                                                                                                               \
                if(!return_addr_ok || !derived_cap || sizeof(struct skadi_subsystem_caller_trampoline) + sizeof(uintptr_t) <= trampoline_code_len){         \
                    SKADI_SUBSYSTEM_ERROR("Could not derive return capability!\n");                                                                         \
                    return false;                                                                                                                           \
                }                                                                                                                                           \
                else{                                                                                                                                       \
                    SKADI_SUBSYSTEM_DEBUG("Got caller trampoline addr 0x%"PRIx64" for subsystem call "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"\n",               \
                                          (uint64_t) derived_cap);                                                                                          \
                }                                                                                                                                           \
                                                                                                                                                            \
                trampoline->registers = &SUBSYS_ENTRY_POINT_NAME##_caller_saved_register_array[i];                                                          \
                                                                                                                                                            \
                trampoline->return_addr = derived_cap;                                                                                                      \
                SUBSYS_ENTRY_POINT_NAME##_caller_trampoline.trampolines[i] = (void *) derived_cap_writable; /* writable permission will persist */          \
                return_addr_ok &= skadi_cap_ops_restrict(trampoline, restriction_writable, 0, 0, 0); /* only used derived cap's from now on */              \
                if(!return_addr_ok){                                                                                                                        \
                    return false;                                                                                                                           \
                }                                                                                                                                           \
            }                                                                                                                                               \
            SKADI_SUBSYSTEM_DECLARE_CALLER_TRAMPOLINES_IRQ(SUBSYS_ENTRY_POINT_NAME)                                                                         \
            return true;                                                                                                                                    \
        }

#if defined(NO_THREADS_IN_CALLEE_TRAMPOLINE) || !defined(CONFIG_SKADI_MARK_THREAD_IN_TRAMPOLINE)

#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_RELOCATE_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)

#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_MARK_CURRENT_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)

#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_RELEASE_CURRENT_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)

#else

#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_MARK_CURRENT_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)                   \
        "ld s1, "STRINGIFY(SUBSYSTEM_ENTRY_POINT_NAME##_caller_trampoline_current_reloc)"\n\t"              \
        "ld s1, 0(s1)\n\t" /* s1 now has address of pointer to current thread */                            \
        "ld s1, 0(s1)\n\t" /* s1 now has address of current thread */                                       \
        /*"beqz s1, "STRINGIFY(SUBSYSTEM_ENTRY_POINT_NAME)"_do_jump\n\t"*/                                  \
        "sd s1, 168(t6)\n\t" /* remember the thread that this stack is associated with in register set*/

#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_RELEASE_CURRENT_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)                          \
        "sd zero, 168(t1)\n\t"


#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_RELOCATE_THREAD(SUBSYSTEM_ENTRY_POINT_NAME)           \
        ".p2align 3\n\t"                                                                        \
        STRINGIFY(SUBSYSTEM_ENTRY_POINT_NAME##_caller_trampoline_current_reloc)":\n\t"          \
        ".dword skadi_sched_current_reloc\n\t" /* address of the address of pointer to current thread*/
#endif /* NO_THREADS_IN_CALLEE_TRAMPOLINE || !CONFIG_SKADI_MARK_THREAD_IN_TRAMPOLINE */

#ifdef CONFIG_SKADI_DEBUG
        #define SKADI_SUBSYSTEM_CALLER_REGSET_SANITY_CHECK(SUBSYS_ENTRY_POINT_NAME)                                                                                                         \
        /* check that the register set was not actually used by someone else */                                                                                                             \
        __asm__ volatile (                                                                                                                                                                  \
            "li s1, 1\n\t"                                                                                                                                                                  \
            "addi t6, t6, 144\n\t" /* amoswap does not have immediate */                                                                                                                    \
            "amoswap.d s1, s1, 0(t6)\n\t"                                                                                                                                                   \
            "beqz s1, "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_do_jump\n\t"                                                                                                                     \
            "j "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_dummy_loop_used\n\t"                                                                                                                    \
            STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_do_jump:\n\t"                                                                                                                               \
        );
        #define SKADI_SUBSYSTEM_CALLER_REGSET_SANITY_CHECK_RESET "sd zero, 144(t1)\n\t" /* set used flag to false */
#else
        #define SKADI_SUBSYSTEM_CALLER_REGSET_SANITY_CHECK(SUBSYS_ENTRY_POINT_NAME) /*nothing*/
        #define SKADI_SUBSYSTEM_CALLER_REGSET_SANITY_CHECK_RESET ""
#endif

#define SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOCHECK(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG) "jr " STRINGIFY(REG) "\n\t"

#ifdef CONFIG_SKADI_SUBSYSTEM_CALL_INSTRUCTIONS

#ifdef CONFIG_SKADI_CHECK_SUBSYSTEM_CALL_ID
#define SKADI_SUBSYSTEM_CALL_IMPORT_TASK_ID(SUBSYS_ENTRY_POINT_NAME)                        \
    ".p2align 2\n\t"                                                                        \
    ".global "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_callee_trampoline_exp_task_id; "          \
    ".type "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_callee_trampoline_exp_task_id, %object\n\t" \
    STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_callee_trampoline_exp_task_id:\n\t"                 \
    ".4byte 0x0\n\t"
/* no particular ID expected */
#define SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOTASK(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG) \
    SKADI_SCALL_STR(REG, 0) "\n\t"

/* for static imports -> assume the loader knows where it came from, make sure we always jump to expected subsystem */
#define SKADI_SUBSYSTEM_CALL_INSTRUCTION(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG)                            \
    "lw " STRINGIFY(ID_REG)", "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_callee_trampoline_exp_task_id\n\t"   \
    SKADI_SCALL_ID_STR(REG,ID_REG) "\n\t"
#else
#define SKADI_SUBSYSTEM_CALL_IMPORT_TASK_ID(SUBSYS_ENTRY_POINT_NAME)
#define SKADI_SUBSYSTEM_CALL_INSTRUCTION(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG) SKADI_SCALL_STR(REG,0) "\n\t"
#define SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOTASK(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG) SKADI_SUBSYSTEM_CALL_INSTRUCTION(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG)
#endif /* CONFIG_SKADI_CHECK_SUBSYSTEM_CALL_ID*/

#define SKADI_SUBSYSTEM_CALL_INSTRUCTION_SELF(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG) SKADI_SCALLS_STR(REG,0) "\n\t"

#else
#define SKADI_SUBSYSTEM_CALL_IMPORT_TASK_ID(SUBSYS_ENTRY_POINT_NAME)
#define SKADI_SUBSYSTEM_CALL_INSTRUCTION(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG) SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOCHECK(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG)
#define SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOTASK(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG) SKADI_SUBSYSTEM_CALL_INSTRUCTION(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG)
#define SKADI_SUBSYSTEM_CALL_INSTRUCTION_SELF(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG) SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOCHECK(SUBSYS_ENTRY_POINT_NAME,REG,ID_REG)
#endif

#ifdef CONFIG_SKADI_FAST_REG_ZERO_INSTRUCTION
#define SKADI_SUBSYSTEM_FAST_REGCLEAR_CALLER(SUBSYS_ENTRY_POINT_NAME)                           \
    __asm__ volatile(                                                                           \
        SKADI_REGCALL_STR(t0)"\n\t"                                                             \
    )

#define SKADI_SUBSYSTEM_FAST_REGCLEAR_CALLER_MASK(SUBSYS_ENTRY_POINT_NAME, NUM_INPUT_ARGS)      \
    __asm__ volatile(                                                                           \
        ".p2align 3\n\t"                                                                        \
        STRINGIFY(SUBSYS_ENTRY_POINT_NAME) "_caller_clear_mask:\n\t"                            \
    );                                                                                          \
    if(NUM_INPUT_ARGS==0){                                                                      \
        __asm__ volatile("li t0, " STRINGIFY(SKADI_CLEAR_REG_CALLER_0_ARGS) "\n\t");            \
    }                                                                                           \
    if(NUM_INPUT_ARGS==1){                                                                      \
        __asm__ volatile("li t0, " STRINGIFY(SKADI_CLEAR_REG_CALLER_1_ARGS) "\n\t");            \
    }                                                                                           \
    if(NUM_INPUT_ARGS==2){                                                                      \
        __asm__ volatile("li t0, " STRINGIFY(SKADI_CLEAR_REG_CALLER_2_ARGS) "\n\t");            \
    }                                                                                           \
    if(NUM_INPUT_ARGS==3){                                                                      \
        __asm__ volatile("li t0, " STRINGIFY(SKADI_CLEAR_REG_CALLER_3_ARGS) "\n\t");            \
    }                                                                                           \
    if(NUM_INPUT_ARGS==4){                                                                      \
        __asm__ volatile("li t0, " STRINGIFY(SKADI_CLEAR_REG_CALLER_4_ARGS) "\n\t");            \
    }                                                                                           \
    if(NUM_INPUT_ARGS==5){                                                                      \
        __asm__ volatile("li t0, " STRINGIFY(SKADI_CLEAR_REG_CALLER_5_ARGS) "\n\t");            \
    }                                                                                           \
    if(NUM_INPUT_ARGS==6){                                                                      \
        __asm__ volatile("li t0, " STRINGIFY(SKADI_CLEAR_REG_CALLER_6_ARGS) "\n\t");            \
    }                                                                                           \
    if(NUM_INPUT_ARGS==7){                                                                      \
        __asm__ volatile("li t0, " STRINGIFY(SKADI_CLEAR_REG_CALLER_7_ARGS) "\n\t");            \
    }                                                                                           \
    if(NUM_INPUT_ARGS==8){                                                                      \
        __asm__ volatile("li t0, " STRINGIFY(SKADI_CLEAR_REG_CALLER_8_ARGS) "\n\t");            \
    }
#else
#define SKADI_SUBSYSTEM_FAST_REGCLEAR_CALLER(SUBSYS_ENTRY_POINT_NAME) /* nothing */
#define SKADI_SUBSYSTEM_FAST_REGCLEAR_CALLER_MASK(SUBSYS_ENTRY_POINT_NAME, NUM_INPUT_ARGS) /* nothing */
#endif


#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALL_ALLOC_ITERATIONS
#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_RELOC(SUBSYS_ENTRY_POINT_NAME)   \
        STRINGIFY(SUBSYS_ENTRY_POINT_NAME) "_alloc_it_reloc_caller:\n\t"              \
        ".dword skadi_subsystem_caller_trampoline_alloc_its\n\t"

#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_ADD_PREPARE(SUBSYS_ENTRY_POINT_NAME)   \
        "li t6, 1\n\t"                                                                      \
        "ld t4, "STRINGIFY(SUBSYS_ENTRY_POINT_NAME) "_alloc_it_reloc_caller\n\t"

#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
/* uniprocessor synchronization - relies on IRQs disabled */
#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_ADD                                \
        "ld t6, 0(t4)\n\t"                                                              \
        "addi t6, t6, 1\n\t"                                                            \
        "sd t6, 0(t4)\n\t"
#else
/* multiprocessor synchronization - relies on atomics */
#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_ADD                                \
        "amoadd.d zero, t6, 0(t4)\n\t"
#endif /* CONFIG_SKADI_SUBSYS_SYNC_UP */
#else
#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_RELOC(SUBSYS_ENTRY_POINT_NAME)
#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_ADD_PREPARE(SUBSYS_ENTRY_POINT_NAME)
#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_ADD
#endif

#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
/* TODO sizeof(void*) hard-coded here... */
#define SKADI_CALLER_TRAMPOLINE_IRQ_SKIP (8+8*CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS)

/* uniprocessor synchronization - relies on IRQs disabled */
#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_PICK_IRQ_NON_IRQ_SET                                                                                  \
        "csrr t3, mstatus\n\t"                                                                                                                  \
        "srli t3, t3, " STRINGIFY(SKADI_NONSTANDARD_MSTATUS_ISR_SHIFT) "\n\t" /* bit 0 is set or unset, depending on mstatus */                 \
        "andi t3, t3, 0x1\n\t" /* clear all bits except 0  */                                                                                   \
        "li t2, "STRINGIFY(SKADI_CALLER_TRAMPOLINE_IRQ_SKIP) "\n\t" /* IRQ skip */                                                              \
        "mul t3, t3, t2\n\t" /* t3 is 0 or IRQ skip now, depending on mstatus */                                                                \
        "add t5, t5, t3\n\t" /* branchless skip of non-IRQ set in IRQ mode */

#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ALLOC_REG_SET(SUBSYS_ENTRY_POINT_NAME)                                                                                                            \
            "ld t3, 0(t5)\n\t" /* load the caller trampoline set - can check occupied, look for first free set; rely on IRQs for sync.  */                                                  \
            SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_ADD                                                                                                                                \
            "beqz t3, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_caller_trampoline)"_start_register_set_search\n\t" /* is zero, i.e., non free -> try again */                                   \
            "ctz t2, t3\n\t" /* t2 is trailing zeros, i.e., first free register set */                                                                                                      \
            "bclr t3, t3, t2\n\t" /* clear the register set - this is ours now! */                                                                                                          \
            "sd t3, 0(t5)\n\t" /* store back - can be sure that no one modified the register in the meantime */
#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_RESTORE_BITMAP                                                                              \
            "ld t4, 0(t2)\n\t"                                                                                                        \
            "or t1, t3, t4\n\t"                                                                                                       \
            "sd t1, 0(t2)\n\t"
#else

#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_PICK_IRQ_NON_IRQ_SET ""

#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ALLOC_REG_SET(SUBSYS_ENTRY_POINT_NAME)                                                                                                            \
            "lr.d t3, 0(t5)\n\t" /* load the caller trampoline set - can check occupied, look for first free set; set load reservation  */                                                  \
            SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_ADD                                                                                                                                \
            "beqz t3, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_caller_trampoline)"_start_register_set_search\n\t" /* is zero, i.e., non free -> try again */                                   \
            "ctz t2, t3\n\t" /* t2 is trailing zeros, i.e., first free register set */                                                                                                      \
            "bclr t3, t3, t2\n\t" /* clear the register set - this is ours now! */                                                                                                          \
            "sc.d t3, t3, 0(t5)\n\t" /* store back - can check if anyone has modified the register in the mean time */                                                                      \
            "bnez t3, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_caller_trampoline)"_start_register_set_search\n\t" /* if someone did modify this address in the meantime: try again */
#define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_RESTORE_BITMAP "amoor.d t4, t3, 0(t2)\n\t" /* set the bit in the free mask atomically, leaving the other bits at their current values --> is available again */

#endif /* CONFIG_SKADI_SUBSYS_SYNC_UP */

#define SKADI_SUBSYSTEM_STUB_GET_TRAMPOLINES(SUBSYS_ENTRY_POINT_NAME)                                                                                                                   \
    __asm__ volatile( /* we need to retrieve the per-subsystem global skadi_subsystem_caller_trampoline, containing return trampolines and register spill spaces */                     \
        "ld t5, ." STRINGIFY(SUBSYS_ENTRY_POINT_NAME) "_skadi_subsystem_caller_trampoline_reloc\n"                                                                                      \
    );


    /* 
     * we assume that the caller of the stub took care of saving its registers on the stack, i.e., we only have to save and restore the callee-saved registers
     * also, the caller of this macro is responsible for moving the set-task-id token into the t1 register
     */
    #define SKADI_SUBSYSTEM_STUB_CALL_NO_RET(SUBSYS_ENTRY_POINT_NAME, NUM_INPUT_ARGS, NUM_VARIADIC_REGS, REG_FIXUPS, SET_SP_GP, CALL_INSTR)                                                 \
        SKADI_SUBSYSTEM_STUB_GET_TRAMPOLINES(SUBSYS_ENTRY_POINT_NAME);                                                                                                                      \
        __asm__ volatile(                                                                                                                                                                   \
            SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_ADD_PREPARE(SUBSYS_ENTRY_POINT_NAME)                                                                                               \
            /* we need to find the first available register set from the wrapper and mark it as used in the bitmap to prevent races */                                                      \
            /* we do this here, where we can still use *most* of our registers */                                                                                                           \
            STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_caller_trampoline)"_start_register_set_search:\n\t"                                                                                         \
            SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_PICK_IRQ_NON_IRQ_SET  "\n\t"                                                                                                                  \
            SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ALLOC_REG_SET (SUBSYS_ENTRY_POINT_NAME) "\n\t"                                                                                                \
            "li t3, 1\n\t" /* prepare restore mask */                                                                                                                                       \
            "sll t3, t3, t2\n\t" /* t3 is restore mask now */                                                                                                                               \
            "slli t2, t2, 3\n\t" /* t2 is our set now - multiply with size of pointer to get actual offset */                                                                               \
            "add t2, t2, t5\n\t" /* t2 = start of register wrapper + offset into register set array */                                                                                      \
            "ld t0, 8(t2)\n\t" /* add 8 (to skip over bitmap) and load the actual trampoline */                                                                                             \
            "ld t6, 32(t0)\n\t" /* load the register set for this trampoline */                                                                                                             \
            "la t2, skadi_subsystem_caller_trampoline_restore_context_"STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"\n\t" /* get epilogue address */                                                  \
            "sd t2, 24(t0)\n\t" /* load return address capability token from trampoline */                                                                                                  \
            "ld t2, 40(t0)\n\t" /* load return address capability token from trampoline */                                                                                                  \
            "sd t3, 152(t6)\n\t" /* save free mask for later */                                                                                                                             \
            "sd t5, 160(t6)\n\t" /* save pointer to trampoline wrapper for faster access during restore */                                                                                  \
        );                                                                                                                                                                                  \
                                                                                                                                                                                            \
                                                                                                                                                                                            \
        __asm__ volatile(                                                                                                                                                                   \
            "sd sp,0(t6)\n\t"                                                                                                                                                               \
            "sd gp,8(t6)\n\t"                                                                                                                                                               \
            "sd tp,16(t6)\n\t"                                                                                                                                                              \
            "sd fp,24(t6)\n\t"                                                                                                                                                              \
            "sd s1,32(t6)\n\t"                                                                                                                                                              \
            "sd s2,40(t6)\n\t"                                                                                                                                                              \
            "sd s3,48(t6)\n\t"                                                                                                                                                              \
            "sd s4,56(t6)\n\t"                                                                                                                                                              \
            "sd s5,64(t6)\n\t"                                                                                                                                                              \
            "sd s6,72(t6)\n\t"                                                                                                                                                              \
            "sd s7,80(t6)\n\t"                                                                                                                                                              \
            "sd s8,88(t6)\n\t"                                                                                                                                                              \
            "sd s9,96(t6)\n\t"                                                                                                                                                              \
            "sd s10,104(t6)\n\t"                                                                                                                                                            \
            "sd s11,112(t6)\n\t"                                                                                                                                                            \
            "sd ra,120(t6)\n\t" /* our original return address */                                                                                                                           \
            "csrr s2, mstatus\n\t" /* interrupt state mstatus */                                                                                                                            \
            "sd s2,128(t6)\n\t" /* save interrupt state */                                                                                                                                  \
            "csrr s1, mie\n\t" /* interrupt enables */                                                                                                                                      \
            "sd s1,136(t6)\n\t" /* save interrupt enabled */                                                                                                                                \
            SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_MARK_CURRENT_THREAD(SUBSYS_ENTRY_POINT_NAME)  /* remember which thread the register set is associated with for cancellation */                \
            "mv ra, t2\n\t" /* set return address */                                                                                                                                        \
            /* we can skip saving the registers in case the FPU has not been touched - this is evident in the mstatus.fs flag */                                                            \
            SKADI_SUBSYSTEM_HANDLE_CALLEE_SAVED_FPU_REGS("li s2,"STRINGIFY(MSTATUS_FS_DIRTY)"\n\tand s1,s1,s2\n\tbeq s1,s2,"STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_fpu_saved\n\t",fsd, t6)     \
            STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_fpu_saved:\n\t"                                                                                                                             \
            "csrci mstatus, " STRINGIFY(MSTATUS_MIE) "\n\t" /* disable timer interrupts - stack about to become invalid */                                                                  \
        );                                                                                                                                                                                  \
        SET_SP_GP; /* init function: initial stack and misappropriated argument, otherwise: zeros */                                                                                        \
        SKADI_SUBSYSTEM_CALLER_REGSET_SANITY_CHECK(SUBSYS_ENTRY_POINT_NAME);                                                                                                                \
        SKADI_SUBSYSTEM_DESTROY_ARGUMENT_REGISTERS(NUM_INPUT_ARGS); /* must not leak arguments from previous calls */                                                                       \
        SKADI_SUBSYSTEM_RESTORE_VARIADIC_ARGUMENT_REGS(NUM_VARIADIC_REGS); /* if necessary, restore argument registers from frame pointer via variadic calls */                             \
        REG_FIXUPS;                                                                                                                                                                         \
        __asm__ volatile (                                                                                                                                                                  \
            SKADI_SUBSYSTEM_DESTROY_REGISTERS_EXCEPT_T1_SP_GP                                                                                                                               \
        );                                                                                                                                                                                  \
        SKADI_SUBSYSTEM_DESTROY_FPU_REGS;                                                                                                                                                   \
        SKADI_SUBSYSTEM_DESTROY_FPU_ARGS(NUM_INPUT_ARGS);                                                                                                                                   \
        SKADI_SUBSYSTEM_FAST_REGCLEAR_CALLER_MASK(SUBSYS_ENTRY_POINT_NAME, NUM_INPUT_ARGS);                                                                                                 \
        SKADI_SUBSYSTEM_FAST_REGCLEAR_CALLER(SUBSYS_ENTRY_POINT_NAME);                                                                                                                      \
        __asm__ volatile (                                                                                                                                                                  \
            SKADI_SUBSYSTEM_FLUSH_BRANCH_TARGET_PREDICTION /* prevent spurious instruction fetches later, causing accidental subsystem calls */                                             \
            SKADI_SUBSYSTEM_FLUSH_CACHES /* make sure all loads/stores are committed */                                                                                                     \
        );                                                                                                                                                                                  \
                                                                                                                                                                                            \
        __asm__ volatile (                                                                                                                                                                  \
                CALL_INSTR(SUBSYS_ENTRY_POINT_NAME,t1,t2)                                                                                                                                                           \
            );                                                                                                                                                                              \
        __asm__ volatile (                                                                                                                                                                  \
            "skadi_subsystem_caller_trampoline_restore_context_"STRINGIFY(SUBSYS_ENTRY_POINT_NAME)":\n\t"                                                                                   \
            SKADI_SUBSYSTEM_FLUSH_CACHES /* prevent microarchitectural leaks */                                                                                                             \
            "csrr t2, mstatus\n\t"                                                                                                                                                          \
            "li t1, 0x1\n\t"                                                                                                                                                                \
            "slli t1, t1, " STRINGIFY(SKADI_NONSTANDARD_MSTATUS_ISR_SHIFT) "\n\t"                                                                                                           \
            "and t1, t1, t2\n\t"                                                                                                                                                            \
            "bnez t1, " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) "_irq_handler_restored\n\t" /* in ISR - sched hook is not writable (and not used!) */                        \
            /* restore interrupt handler, leaving t0 (start of structure with epilogue address + callee-saved register) alive */                                                            \
            "la t1, _skadi_subsystem_yield_stub\n\t"                                                                                                                                        \
            "csrw " STRINGIFY(SKADI_MTIMER_HOOK_CSR) ", t1\n\t" /* HAS to be set via CSR to prevent loader / ISR handler from manipulation */                                               \
            STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline)"_irq_handler_restored:\n\t"                                                                                              \
            "ld t1, 28(t0)\n\t" /* get caller-saved registers struct into t1*/                                                                                                              \
            "ld sp,0(t1)\n\t"                                                                                                                                                               \
            /* we have registered the interrupt handler and restored the stack pointer - ready to restore interrupts to previous value */                                                   \
            "ld s1,136(t1)\n\t" /* get interrupt enabled */                                                                                                                                 \
            "csrw mie, s1\n\t" /* set interrupt enables */                                                                                                                                  \
            "ld s1,128(t1)\n\t" /* get interrupt state */                                                                                                                                   \
            "csrw mstatus, s1\n\t" /* set interrupt state */                                                                                                                                \
            SKADI_SUBSYSTEM_CALLER_REGSET_SANITY_CHECK_RESET                                                                                                                                \
            "ld gp,8(t1)\n\t"                                                                                                                                                               \
            "ld tp,16(t1)\n\t"                                                                                                                                                              \
            "ld fp,24(t1)\n\t"                                                                                                                                                              \
            "ld s1,32(t1)\n\t"                                                                                                                                                              \
            "ld s2,40(t1)\n\t"                                                                                                                                                              \
            "ld s3,48(t1)\n\t"                                                                                                                                                              \
            "ld s4,56(t1)\n\t"                                                                                                                                                              \
            "ld s5,64(t1)\n\t"                                                                                                                                                              \
            "ld s6,72(t1)\n\t"                                                                                                                                                              \
            "ld s7,80(t1)\n\t"                                                                                                                                                              \
            "ld s8,88(t1)\n\t"                                                                                                                                                              \
            "ld s9,96(t1)\n\t"                                                                                                                                                              \
            "ld s10,104(t1)\n\t"                                                                                                                                                            \
            "ld s11,112(t1)\n\t"                                                                                                                                                            \
            "ld ra,120(t1)\n\t"                                                                                                                                                             \
            SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_RELEASE_CURRENT_THREAD(SUBSYS_ENTRY_POINT_NAME)                                                                                               \
            SKADI_SUBSYSTEM_HANDLE_CALLEE_SAVED_FPU_REGS(/* nothing */, fld, t1)                                                                                                            \
            SKADI_SUBSYSTEM_SET_FPU_COMMAND(t2) /* FPU might have been disabled during the call */                                                                                          \
            /* we still need to free the caller trampoline in the bitmap */                                                                                                                 \
            "ld t2, 160(t1)\n\t" /* restore the trampoline wrapper which contains the bitmap */                                                                                             \
            "ld t3, 152(t1)\n\t" /* restore the free mask */                                                                                                                                \
            SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_RESTORE_BITMAP "\n\t"                                                                                                                         \
            "and t4, t4, t3\n\t" /* check if the free bit was set */                                                                                                                        \
            "bnez t4, "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_dummy_loop_used\n\t" /* free bit was set - someone is replaying, we handle the error by not returning */                         \
        );

#ifdef CONFIG_PROFILING_PERF
    #define SKADI_SUBSYSTEM_CALL_SUB_PROLOGUE                                                                                                                       \
        __asm__ volatile (                                                                                                                                          \
        "addi sp, sp, -16\n\t"         /* Allocate space for return address on stack, keeping alignment */                                                          \
        SKADI_SUBSYSTEM_SAVE_PREVIOUS_SP                                                                                                                            \
        "sd ra, 8(sp)\n\t"                                                                                                                                          \
        )
    #define SKADI_SUBSYSTEM_CALL_SUB_EPILOGUE   \
        __asm__ volatile (                      \
            SKADI_SUBSYSTEM_RESTORE_PREVIOUS_SP \
            "addi sp, sp, 16\n\t"               \
        )
#else
    #define SKADI_SUBSYSTEM_CALL_SUB_PROLOGUE
    #define SKADI_SUBSYSTEM_CALL_SUB_EPILOGUE
#endif

    #define SKADI_SUBSYSTEM_STUB_DO_CALL(SUBSYS_ENTRY_POINT_NAME, NUM_INPUT_ARGS,                                                                                               \
            NUM_VAR, REGISTER_FIXUP, SET_SP_GP, CALL_INSTR)                                                                                                                     \
            SKADI_SUBSYSTEM_CALL_SUB_PROLOGUE;                                                                                                                                  \
        SKADI_SUBSYSTEM_STUB_CALL_NO_RET(SUBSYS_ENTRY_POINT_NAME, NUM_INPUT_ARGS, NUM_VAR, REGISTER_FIXUP, SET_SP_GP, CALL_INSTR)                                               \
        SKADI_SUBSYSTEM_CALL_SUB_EPILOGUE;                                                                                                                                      \
        __asm__ volatile(                                                                                                                                                       \
                "ret\n\t"                                                                                                                                                       \
                STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_dummy_loop_used:\n\t"                                                                                                       \
                "j "STRINGIFY(SUBSYS_ENTRY_POINT_NAME)"_dummy_loop_used\n\t"                                                                                                    \
                ".p2align 3\n" /* needs to be 8-bit aligned for the load to work */                                                                                             \
                "." STRINGIFY(SUBSYS_ENTRY_POINT_NAME) "_skadi_subsystem_caller_trampoline_reloc:\n"                                                                            \
                ".dword skadi_subsystem_caller_trampoline\n" /* address of the trampoline pointer */                                                                            \
                SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_RELOCATE_THREAD(SUBSYS_ENTRY_POINT_NAME)                                                                                      \
                SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ITERATIONS_RELOC(SUBSYS_ENTRY_POINT_NAME)                                                                                     \
                SKADI_SUBSYSTEM_CALL_IMPORT_TASK_ID(SUBSYS_ENTRY_POINT_NAME)                                                                                                    \
        );


    /* credit: https://stackoverflow.com/a/16926582 */
    /* FIXME this breaks as soon as floating-point args are involved */
    #define SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(...) SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS_(,##__VA_ARGS__,8,7,6,5,4,3,2,1,0)                         
    #define SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS_(z,a,b,c,d,e,f,g,h,cnt,...) cnt


    #define SKADI_CLEAR_SP_GP __asm__ volatile (                                                                                                            \
                "mv sp, zero\n"                                                                                                                             \
                "mv gp, zero\n"                                                                                                                             \
             )
    
    #define SKADI_MOVE_CALLEE_TRAMPOLINE_INTO_REG(SUBSYS_ENTRY_POINT_NAME, REG)                                                             \
        __asm__ volatile(                                                                                                                   \
            "j ." STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_reloc_load)"\n"                                                     \
            ".p2align 3\n" /* needs to be 8-bit aligned for the load to work */                                                             \
            "." STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_reloc)":\n"                                                           \
            ".dword " STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline) "\n" /* address of function */                                 \
            "."STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_reloc_load)":\n"                                                       \
            "ld " STRINGIFY(REG) ", ." STRINGIFY(SUBSYS_ENTRY_POINT_NAME##_callee_trampoline_reloc)"\n" /* "near" relocation suffices*/     \
        )
    
    #define SKADI_MOVE_NAMED_ARG_INTO_REG(ARG, REG)                                                                                         \
        __asm__ volatile(                                                                                                                   \
            "mv " REG ", %0" :: "r" (ARG)                                                                                                   \
        )                                                                                                                                   \

    /* these methods need explicit number of arguments, as one might be implicit (VALIST); also, name of the callee trampoline is explicit too */

    /* implementation for non-void (!) subsystem caller trampoline */

    #define _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_IMPL(RET_INSTR, SUFFIX, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, ...)    \
        extern SUBSYS_ENTRY_POINT_RETVAL CONCAT(CALLEE_TR_NAME, callee_trampoline) (__VA_ARGS__);                                                                   \
        SUBSYS_ENTRY_POINT_RETVAL __attribute__((naked))                                                                                                            \
            CONCAT(__skadi_caller_trampoline_,VAPFX,retval,SUFFIX,__,SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __,SUBSYS_ENTRY_POINT_NAME)                  \
                (__VA_ARGS__){                                                                                                                                      \
            __asm__ volatile (                                                                                                                                      \
                ".type " STRINGIFY(CONCAT(CALLEE_TR_NAME, _callee_trampoline)) ",%function\n"                                                                       \
            );                                                                                                                                                      \
            SKADI_MOVE_CALLEE_TRAMPOLINE_INTO_REG(CALLEE_TR_NAME, t1);                                                                                              \
            SKADI_SUBSYSTEM_STUB_DO_CALL(SUBSYS_ENTRY_POINT_NAME,NUM_ARGS,                                                                                          \
            0, /* nothing */,  SKADI_CLEAR_SP_GP, RET_INSTR);                                                                                                       \
        }
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_IMPL(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, ...)                                           \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION, , SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, __VA_ARGS__)

    /* 
     * For loader-resolved caller trampolines (imported by name), we might be using our own local symbol directly - cannot use subsystem call instruction
     * No security risk, as the loader ensures proper callable capabilities are provided here
     */
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_IMPL_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, ...)                                                                 \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOCHECK, _allow_self, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, __VA_ARGS__)
    
    
    /* implementation for void (!) subsystem caller trampoline */
    #define _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID_IMPL(RET_INSTR, SUFFIX, SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, ...)              \
        extern void CONCAT(CALLEE_TR_NAME, callee_trampoline) (__VA_ARGS__);                                                                            \
        void __attribute__((naked))                                                                                                                     \
            CONCAT(__skadi_caller_trampoline_,VAPFX,void_,SUFFIX,_,SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)       \
                (__VA_ARGS__){                                                                                                                          \
            __asm__ volatile (                                                                                                                          \
                ".type " STRINGIFY(CONCAT(CALLEE_TR_NAME, _callee_trampoline)) ",%function\n"                                                           \
            );                                                                                                                                          \
            SKADI_MOVE_CALLEE_TRAMPOLINE_INTO_REG(CALLEE_TR_NAME, t1);                                                                                  \
            SKADI_SUBSYSTEM_STUB_DO_CALL(SUBSYS_ENTRY_POINT_NAME,NUM_ARGS,                                                                              \
            0, /* nothing */,  SKADI_CLEAR_SP_GP, RET_INSTR);                                                                                           \
        }
    
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID_IMPL(SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, ...)                                                          \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION, , SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, __VA_ARGS__)
    
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID_IMPL_ALLOW_SELF(SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, ...)                                               \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOCHECK, allow_self_, SUBSYS_ENTRY_POINT_NAME, CALLEE_TR_NAME, VAPFX, NUM_ARGS, __VA_ARGS__)

    /* implementation for function pointer subsystem caller trampoline */
    #define _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_IMPL(RET_INSTR, SUFFIX, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  ...)           \
        SUBSYS_ENTRY_POINT_RETVAL __attribute__((naked)) CONCAT(__skadi_caller_trampoline_fn_ptr_retval_,SUFFIX,_,                                          \
            SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__ __VA_OPT__(,)                                        \
                                                                                    SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)(__VA_ARGS__)){                      \
            SKADI_MOVE_NAMED_ARG_INTO_REG(fn_ptr, "t1");                                                                                                    \
            SKADI_SUBSYSTEM_STUB_DO_CALL(SUBSYS_ENTRY_POINT_NAME,                                                                                           \
                                        NUM_ARGS, 0, /* nothing */,  SKADI_CLEAR_SP_GP, RET_INSTR);                                                         \
    }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_IMPL(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  ...)                                                           \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOTASK, ,SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  __VA_ARGS__)

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_IMPL_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  ...)                                                \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_SELF, allow_self_,SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  __VA_ARGS__)

    #define _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_IMPL(RET_INSTR, SUFFIX, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  ...)        \
        SUBSYS_ENTRY_POINT_RETVAL __attribute__((naked)) CONCAT(__skadi_caller_trampoline_fn_ptr_va_retval_,SUFFIX,_,                                       \
            SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__, va_list args,                                       \
                                                                                    SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)(__VA_ARGS__)){                      \
            SKADI_MOVE_NAMED_ARG_INTO_REG(fn_ptr, "t1");                                                                                                    \
            SKADI_SUBSYSTEM_STUB_DO_CALL(SUBSYS_ENTRY_POINT_NAME,                                                                                           \
                                        NUM_ARGS, 0, /* nothing */,  SKADI_CLEAR_SP_GP, RET_INSTR);                                                         \
    }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_IMPL(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  ...)                                    \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOTASK,, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  __VA_ARGS__)

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_IMPL_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  ...)                                                    \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_SELF, allow_self_, SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS,  __VA_ARGS__)

    /* implementation for function pointer void subsystem caller trampoline */
    #define _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_IMPL(RET_INST, SUFFIX, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, ...)                       \
        void __attribute__((naked)) CONCAT(__skadi_caller_trampoline_fn_ptr_void_, SUFFIX,_,SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__),   \
        __, SUBSYS_ENTRY_POINT_NAME) (__VA_ARGS__, void (*fn_ptr)(__VA_ARGS__)){                                                                \
            SKADI_MOVE_NAMED_ARG_INTO_REG(fn_ptr, "t1");                                                                                        \
            SKADI_SUBSYSTEM_STUB_DO_CALL(SUBSYS_ENTRY_POINT_NAME,                                                                               \
                                        NUM_ARGS, 0, /* nothing */,  SKADI_CLEAR_SP_GP, RET_INST);                                              \
    }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_IMPL(SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, ...)                                          \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOTASK, ,SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, __VA_ARGS__)

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_IMPL_ALLOW_SELF(SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, ...)                                               \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_SELF, allow_self_,SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, __VA_ARGS__)

    /* implementation for function pointer void subsystem caller trampoline */
    #define _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_VOID_IMPL(RET_INSTR, SUFFIX, SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, ...)                                       \
        void __attribute__((naked)) CONCAT(__skadi_caller_trampoline_fn_ptr_va_void_,SUFFIX,_,SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__),                     \
        __, SUBSYS_ENTRY_POINT_NAME) (__VA_ARGS__, va_list args, void (*fn_ptr)(__VA_ARGS__)){                                                                      \
            SKADI_MOVE_NAMED_ARG_INTO_REG(fn_ptr, "t1");                                                                                                            \
            SKADI_SUBSYSTEM_STUB_DO_CALL(SUBSYS_ENTRY_POINT_NAME,                                                                                                   \
                                        NUM_ARGS, 0, /* nothing */,  SKADI_CLEAR_SP_GP, SKADI_SUBSYSTEM_CALL_INSTRUCTION);                                          \
    }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_VOID_IMPL(SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, ...)                                                           \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_VOID_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOTASK, ,SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, __VA_ARGS__)
    
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_VOID_IMPL_ALLOW_SELF(SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, ...)                                                \
        _SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VA_VOID_IMPL(SKADI_SUBSYSTEM_CALL_INSTRUCTION_SELF, allow_self_ ,SUBSYS_ENTRY_POINT_NAME, NUM_ARGS, __VA_ARGS__)
    
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)                                                                                  \
        /* name encodes presence / absence of return value and number of arguments - as we only support arguments in argument registers, this suffices to generate the implementation*/ \
        extern SUBSYS_ENTRY_POINT_RETVAL CONCAT(__skadi_caller_trampoline_retval__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME) (__VA_ARGS__);       \
        static SUBSYS_ENTRY_POINT_RETVAL (*SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__) __attribute__((__unused__)) =                                                                          \
                CONCAT(__skadi_caller_trampoline_retval__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)                                                                                   \
        /* name encodes presence / absence of return value and number of arguments - as we only support arguments in argument registers, this suffices to generate the implementation*/             \
        extern SUBSYS_ENTRY_POINT_RETVAL CONCAT(__skadi_caller_trampoline_retval_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME) (__VA_ARGS__);        \
        static SUBSYS_ENTRY_POINT_RETVAL (*SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__) __attribute__((__unused__)) =                                                                                      \
                CONCAT(__skadi_caller_trampoline_retval_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)


    #define SKADI_SUBSYSTEM_REMOVE_PARENTHESIS(...) __VA_ARGS__

    /**
     * Provides a variadic function declaration that wraps a subsystem call that accepts a va_list.
     * Examples:
     * 
     * SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VALIST(int, foo, SKADI_SUBSYSTEM_REMOVE_PARENTHESIS(format), const char *format)
     * provides this wrapper:
     * int foo(const char *format, ...)
     * invokes a subsystem call declared like this (notice change from elipses to va_list):
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __foo, const char *format, va_list args)
     * 
     * SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VALIST(int, bar, SKADI_SUBSYSTEM_REMOVE_PARENTHESIS(format, something), const char *format, int something)
     * provides this wrapper:
     * int bar(const char *format, int something, ...)
     * invokes a subsystem call declared like this (notice change from elipses to va_list):
     * SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __bar, const char *format, int something, va_list args)
     * 
     * 
     * Limitations:
     * - only handles values that fit into integer register (no floats, no structures, but pointers and int scalars)
     */
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VALIST(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ARG_NAMES_WITHOUT_TYPE, ...)                       \
        extern SUBSYS_ENTRY_POINT_RETVAL                                                                                                                    \
            CONCAT(__skadi_caller_trampoline_va_retval__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME) (__VA_ARGS__,      \
                                                                                                                                          va_list arg);     \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__))                                                                                                      \
                SUBSYS_ENTRY_POINT_RETVAL _##SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) size_t num_var_args, ...){                                   \
            va_list args, args_copy;                                                                                                                        \
            SUBSYS_ENTRY_POINT_RETVAL ret;                                                                                                                  \
                                                                                                                                                            \
            va_start(args, num_var_args);                                                                                                                   \
                                                                                                                                                            \
            args_copy = skadi_valist_clone(args, num_var_args, false);                                                                                      \
            ret = CONCAT(__skadi_caller_trampoline_va_retval__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(             \
                        ARG_NAMES_WITHOUT_TYPE, args_copy                                                                                                   \
            );                                                                                                                                              \
                                                                                                                                                            \
            skadi_cloned_valist_free(args_copy);                                                                                                            \
                                                                                                                                                            \
            va_end(args);                                                                                                                                   \
                                                                                                                                                            \
            return ret;                                                                                                                                     \
        }	                                                                                                                                                \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__)) SUBSYS_ENTRY_POINT_RETVAL SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) ...){                    \
            size_t num_var_args = __builtin_va_arg_pack_len();                                                                                              \
                                                                                                                                                            \
            return _##SUBSYS_ENTRY_POINT_NAME(ARG_NAMES_WITHOUT_TYPE, num_var_args, __builtin_va_arg_pack());                                               \
        }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VALIST_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ARG_NAMES_WITHOUT_TYPE, ...)            \
        extern SUBSYS_ENTRY_POINT_RETVAL                                                                                                                    \
            CONCAT(__skadi_caller_trampoline_va_retval_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(        \
                                                                                                                                          __VA_ARGS__,      \
                                                                                                                                          va_list arg);     \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__))                                                                                                      \
                SUBSYS_ENTRY_POINT_RETVAL _##SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) size_t num_var_args, ...){                                   \
            va_list args, args_copy;                                                                                                                        \
            SUBSYS_ENTRY_POINT_RETVAL ret;                                                                                                                  \
                                                                                                                                                            \
            va_start(args, num_var_args);                                                                                                                   \
                                                                                                                                                            \
            args_copy = skadi_valist_clone(args, num_var_args, false);                                                                                      \
            ret = CONCAT(__skadi_caller_trampoline_va_retval_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(  \
                        ARG_NAMES_WITHOUT_TYPE, args_copy                                                                                                   \
            );                                                                                                                                              \
                                                                                                                                                            \
            skadi_cloned_valist_free(args_copy);                                                                                                            \
                                                                                                                                                            \
            va_end(args);                                                                                                                                   \
                                                                                                                                                            \
            return ret;                                                                                                                                     \
        }	                                                                                                                                                \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__)) SUBSYS_ENTRY_POINT_RETVAL SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) ...){                    \
            size_t num_var_args = __builtin_va_arg_pack_len();                                                                                              \
                                                                                                                                                            \
            return _##SUBSYS_ENTRY_POINT_NAME(ARG_NAMES_WITHOUT_TYPE, num_var_args, __builtin_va_arg_pack());                                               \
        }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(SUBSYS_ENTRY_POINT_NAME, ...)                                                                            \
    extern void                                                                                                                                             \
    CONCAT(__skadi_caller_trampoline_void__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME) (__VA_ARGS__);                  \
    static void (*SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__) __attribute__((__unused__))                                                                         \
        = CONCAT(__skadi_caller_trampoline_void__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID_ALLOW_SELF(SUBSYS_ENTRY_POINT_NAME, ...)                                                                 \
    extern void                                                                                                                                             \
    CONCAT(__skadi_caller_trampoline_void_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME) (__VA_ARGS__);       \
    static void (*SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__) __attribute__((__unused__))                                                                         \
        = CONCAT(__skadi_caller_trampoline_void_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)
    
    /*
     * See non-void version.
     */
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VALIST_VOID(SUBSYS_ENTRY_POINT_NAME, ARG_NAMES_WITHOUT_TYPE, ...)                                             \
    extern void                                                                                                                                             \
        CONCAT(__skadi_caller_trampoline_va_void__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__);            \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__))                                                                                                      \
                void _##SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) size_t num_var_args, ...){                                                        \
            va_list args, args_copy;                                                                                                                        \
                                                                                                                                                            \
            va_start(args, num_var_args);                                                                                                                   \
                                                                                                                                                            \
            args_copy = skadi_valist_clone(args, num_var_args, false);                                                                                      \
            CONCAT(__skadi_caller_trampoline_va_void__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(                     \
                ARG_NAMES_WITHOUT_TYPE, args_copy                                                                                                           \
            );                                                                                                                                              \
                                                                                                                                                            \
            skadi_cloned_valist_free(args_copy);                                                                                                            \
                                                                                                                                                            \
            va_end(args);                                                                                                                                   \
                                                                                                                                                            \
        }	                                                                                                                                                \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__)) void SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) ...){                                         \
            size_t num_var_args = __builtin_va_arg_pack_len();                                                                                              \
                                                                                                                                                            \
            _##SUBSYS_ENTRY_POINT_NAME(ARG_NAMES_WITHOUT_TYPE, num_var_args, __builtin_va_arg_pack());                                                      \
        }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VALIST_VOID_ALLOW_SELF(SUBSYS_ENTRY_POINT_NAME, ARG_NAMES_WITHOUT_TYPE, ...)                                  \
    extern void                                                                                                                                             \
        CONCAT(__skadi_caller_trampoline_va_void_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__); \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__))                                                                                                      \
                void _##SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) size_t num_var_args, ...){                                                        \
            va_list args, args_copy;                                                                                                                        \
                                                                                                                                                            \
            va_start(args, num_var_args);                                                                                                                   \
                                                                                                                                                            \
            args_copy = skadi_valist_clone(args, num_var_args, false);                                                                                      \
            CONCAT(__skadi_caller_trampoline_va_void_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(          \
                ARG_NAMES_WITHOUT_TYPE, args_copy                                                                                                           \
            );                                                                                                                                              \
                                                                                                                                                            \
            skadi_cloned_valist_free(args_copy);                                                                                                            \
                                                                                                                                                            \
            va_end(args);                                                                                                                                   \
                                                                                                                                                            \
        }	                                                                                                                                                \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__)) void SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) ...){                                         \
            size_t num_var_args = __builtin_va_arg_pack_len();                                                                                              \
                                                                                                                                                            \
            _##SUBSYS_ENTRY_POINT_NAME(ARG_NAMES_WITHOUT_TYPE, num_var_args, __builtin_va_arg_pack());                                                      \
        }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_INIT_FN(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME)                                                   \
        _Pragma("GCC diagnostic push")                                                                                                                      \
        _Pragma("GCC diagnostic ignored \"-Wunused-function\"") /* might be in header, where the includer might never call it */                            \
        /* assigned_task_id is passed on to the subsystem; hence, it needs to be in the a0 reg and we indicate 1 argument statically */                     \
        static SUBSYS_ENTRY_POINT_RETVAL __attribute__ ((noinline)) __attribute__((naked)) SUBSYS_ENTRY_POINT_NAME(                                         \
                                                                                            uintptr_t init_fn,uint8_t *top_of_stack, uintptr_t real_init){  \
            SKADI_MOVE_NAMED_ARG_INTO_REG(init_fn, "t1");                                                                                                   \
            SKADI_SUBSYSTEM_STUB_DO_CALL(SUBSYS_ENTRY_POINT_NAME, 0, 0, ,                                                                                   \
            __asm__ volatile (                                                                                                                              \
            "mv sp, %0\n\t" :: "r" (top_of_stack) /* bootstrap stack (init function) or 0*/                                                                 \
            );                                                                                                                                              \
            __asm__ volatile (                                                                                                                              \
                "mv gp, %0\n\t" :: "r" (real_init) /* init function or 0, we abuse the ABI here */                                                          \
            );,                                                                                                                                             \
            SKADI_SUBSYSTEM_CALL_INSTRUCTION_NOCHECK /* loader creates the callee trampolines itself  */                                                    \
        );                                                                                                                                                  \
        }                                                                                                                                                   \
        _Pragma("GCC diagnostic pop")
    
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)                                                                          \
        extern SUBSYS_ENTRY_POINT_RETVAL                                                                                                                                                    \
        CONCAT(__skadi_caller_trampoline_fn_ptr_retval__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__ __VA_OPT__(,)                          \
                                                                                                                                      SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)(__VA_ARGS__));    \
        static SUBSYS_ENTRY_POINT_RETVAL (*SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__ __VA_OPT__(,)                                                                                               \
                                                                    SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)(__VA_ARGS__)) __attribute__((__unused__)) =                                         \
            CONCAT(__skadi_caller_trampoline_fn_ptr_retval__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ...)                                                               \
        extern SUBSYS_ENTRY_POINT_RETVAL                                                                                                                                                    \
        CONCAT(__skadi_caller_trampoline_fn_ptr_retval_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__ __VA_OPT__(,)               \
                                                                                                                                      SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)(__VA_ARGS__));    \
        static SUBSYS_ENTRY_POINT_RETVAL (*SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__ __VA_OPT__(,)                                                                                               \
                                                                    SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)(__VA_ARGS__)) __attribute__((__unused__)) =                                         \
            CONCAT(__skadi_caller_trampoline_fn_ptr_retval_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)
    
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(SUBSYS_ENTRY_POINT_NAME, ...)                                                                \
        extern void                                                                                                                                         \
            CONCAT(__skadi_caller_trampoline_fn_ptr_void__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME) (__VA_ARGS__,    \
                                                                                                                           void (*fn_ptr)(__VA_ARGS__));    \
        static void (*SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__, void (*fn_ptr)(__VA_ARGS__)) __attribute__((__unused__)) =                                      \
            CONCAT(__skadi_caller_trampoline_fn_ptr_void__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)
    
    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS_ALLOW_SELF(SUBSYS_ENTRY_POINT_NAME, ...)                                                                 \
        extern void                                                                                                                                                     \
            CONCAT(__skadi_caller_trampoline_fn_ptr_void_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME) (__VA_ARGS__,     \
                                                                                                                           void (*fn_ptr)(__VA_ARGS__));                \
        static void (*SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__, void (*fn_ptr)(__VA_ARGS__)) __attribute__((__unused__)) =                                                  \
            CONCAT(__skadi_caller_trampoline_fn_ptr_void_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME)                                                    \
        extern SUBSYS_ENTRY_POINT_RETVAL                                                                                                                    \
        CONCAT(__skadi_caller_trampoline_fn_ptr_retval__0__, SUBSYS_ENTRY_POINT_NAME) (SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)());                              \
        SUBSYS_ENTRY_POINT_RETVAL (*SUBSYS_ENTRY_POINT_NAME)() __attribute__((__unused__)) =                                                                \
            CONCAT(__skadi_caller_trampoline_fn_ptr_retval__0__, SUBSYS_ENTRY_POINT_NAME)

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME)                                         \
        extern SUBSYS_ENTRY_POINT_RETVAL                                                                                                                    \
        CONCAT(__skadi_caller_trampoline_fn_ptr_retval_allow_self__0__, SUBSYS_ENTRY_POINT_NAME) (SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)());                   \
        SUBSYS_ENTRY_POINT_RETVAL (*SUBSYS_ENTRY_POINT_NAME)() __attribute__((__unused__)) =                                                                \
            CONCAT(__skadi_caller_trampoline_fn_ptr_retval_allow_self__0__, SUBSYS_ENTRY_POINT_NAME)

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS_VALIST(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ARG_NAMES_WITHOUT_TYPE, ...)                               \
        extern SUBSYS_ENTRY_POINT_RETVAL                                                                                                                                        \
        CONCAT(__skadi_caller_trampoline_fn_ptr_va_retval__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__, va_list arg,           \
                                                                                                                           SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)(__VA_ARGS__,     \
                                                                                                                                                               va_list arg));   \
                                                                                                                                                                                \
        typedef SUBSYS_ENTRY_POINT_RETVAL(*SUBSYS_ENTRY_POINT_NAME##_fn_t)(__VA_ARGS__,va_list arg);                                                                            \
        static inline __attribute__ ((__gnu_inline__))  SUBSYS_ENTRY_POINT_RETVAL                                                                                               \
                _##SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) SUBSYS_ENTRY_POINT_NAME##_fn_t fn_ptr, size_t num_var_args, ...){                                          \
            va_list args, args_copy;                                                                                                                                            \
            SUBSYS_ENTRY_POINT_RETVAL  ret;                                                                                                                                     \
                                                                                                                                                                                \
            va_start(args, num_var_args);                                                                                                                                       \
                                                                                                                                                                                \
            args_copy = skadi_valist_clone(args, num_var_args, false);                                                                                                          \
            ret = CONCAT(__skadi_caller_trampoline_fn_ptr_va_retval__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(ARG_NAMES_WITHOUT_TYPE,   \
                                                                                                                                                  args_copy, fn_ptr);           \
                                                                                                                                                                                \
            skadi_cloned_valist_free(args_copy);                                                                                                                                \
                                                                                                                                                                                \
            va_end(args);                                                                                                                                                       \
                                                                                                                                                                                \
            return ret;                                                                                                                                                         \
        }	                                                                                                                                                                    \
                                                                                                                                                                                \
        static inline __attribute__ ((__gnu_inline__)) SUBSYS_ENTRY_POINT_RETVAL  SUBSYS_ENTRY_POINT_NAME(                                                                      \
                                                                                    __VA_ARGS__ __VA_OPT__(,) SUBSYS_ENTRY_POINT_NAME##_fn_t fn_ptr, ...){                      \
            size_t num_var_args = __builtin_va_arg_pack_len();                                                                                                                  \
                                                                                                                                                                                \
            return _##SUBSYS_ENTRY_POINT_NAME(ARG_NAMES_WITHOUT_TYPE, fn_ptr, num_var_args, __builtin_va_arg_pack());                                                           \
        }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS_VALIST_ALLOW_SELF(SUBSYS_ENTRY_POINT_RETVAL, SUBSYS_ENTRY_POINT_NAME, ARG_NAMES_WITHOUT_TYPE, ...)                                \
        extern SUBSYS_ENTRY_POINT_RETVAL                                                                                                                                                    \
        CONCAT(__skadi_caller_trampoline_fn_ptr_va_retval_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__, va_list arg,            \
                                                                                                                           SUBSYS_ENTRY_POINT_RETVAL (*fn_ptr)(__VA_ARGS__,                 \
                                                                                                                                                               va_list arg));               \
                                                                                                                                                                                            \
        typedef SUBSYS_ENTRY_POINT_RETVAL(*SUBSYS_ENTRY_POINT_NAME##_fn_t)(__VA_ARGS__,va_list arg);                                                                                        \
        static inline __attribute__ ((__gnu_inline__))  SUBSYS_ENTRY_POINT_RETVAL                                                                                                           \
                _##SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) SUBSYS_ENTRY_POINT_NAME##_fn_t fn_ptr, size_t num_var_args, ...){                                                      \
            va_list args, args_copy;                                                                                                                                                        \
            SUBSYS_ENTRY_POINT_RETVAL  ret;                                                                                                                                                 \
                                                                                                                                                                                            \
            va_start(args, num_var_args);                                                                                                                                                   \
                                                                                                                                                                                            \
            args_copy = skadi_valist_clone(args, num_var_args, false);                                                                                                                      \
            ret = CONCAT(__skadi_caller_trampoline_fn_ptr_va_retval_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __, SUBSYS_ENTRY_POINT_NAME)(ARG_NAMES_WITHOUT_TYPE,    \
                                                                                                                                                  args_copy, fn_ptr);                       \
                                                                                                                                                                                            \
            skadi_cloned_valist_free(args_copy);                                                                                                                                            \
                                                                                                                                                                                            \
            va_end(args);                                                                                                                                                                   \
                                                                                                                                                                                            \
            return ret;                                                                                                                                                                     \
        }	                                                                                                                                                                                \
                                                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__)) SUBSYS_ENTRY_POINT_RETVAL  SUBSYS_ENTRY_POINT_NAME(                                                                                  \
                                                                                    __VA_ARGS__ __VA_OPT__(,) SUBSYS_ENTRY_POINT_NAME##_fn_t fn_ptr, ...){                                  \
            size_t num_var_args = __builtin_va_arg_pack_len();                                                                                                                              \
                                                                                                                                                                                            \
            return _##SUBSYS_ENTRY_POINT_NAME(ARG_NAMES_WITHOUT_TYPE, fn_ptr, num_var_args, __builtin_va_arg_pack());                                                                       \
        }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS_VALIST(SUBSYS_ENTRY_POINT_NAME, ARG_NAMES_WITHOUT_TYPE, ...)                                 \
    extern void                                                                                                                                             \
    CONCAT(__skadi_caller_trampoline_fn_ptr_va_void__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __,SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__,           \
                                                                                                                                  va_list arg,              \
                                                                                                                                  void(*fn_ptr)(__VA_ARGS__,\
                                                                                                                                      va_list arg));        \
                                                                                                                                                            \
        typedef void(*SUBSYS_ENTRY_POINT_NAME##_fn_t)(__VA_ARGS__);                                                                                         \
        static inline __attribute__ ((__gnu_inline__))                                                                                                      \
                void _##SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) SUBSYS_ENTRY_POINT_NAME##_fn_t fn_ptr, size_t num_var_args, ...){                 \
            va_list args, args_copy;                                                                                                                        \
                                                                                                                                                            \
            va_start(args, num_var_args);                                                                                                                   \
                                                                                                                                                            \
            args_copy = skadi_valist_clone(args, num_var_args, false);                                                                                      \
            CONCAT(__skadi_caller_trampoline_fn_ptr_va_void__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __,SUBSYS_ENTRY_POINT_NAME)(               \
                                                                                                ARG_NAMES_WITHOUT_TYPE, args_copy, fn_ptr);                 \
                                                                                                                                                            \
            skadi_cloned_valist_free(args_copy);                                                                                                            \
                                                                                                                                                            \
            va_end(args);                                                                                                                                   \
                                                                                                                                                            \
        }	                                                                                                                                                \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__)) void SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) SUBSYS_ENTRY_POINT_NAME##_fn_t fn_ptr, ...){  \
            size_t num_var_args = __builtin_va_arg_pack_len();                                                                                              \
                                                                                                                                                            \
            _##SUBSYS_ENTRY_POINT_NAME(ARG_NAMES_WITHOUT_TYPE, fn_ptr, num_var_args, __builtin_va_arg_pack());                                              \
        }

    #define SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS_VALIST_ALLOW_SELF(SUBSYS_ENTRY_POINT_NAME, ARG_NAMES_WITHOUT_TYPE, ...)                      \
    extern void                                                                                                                                             \
    CONCAT(__skadi_caller_trampoline_fn_ptr_va_void_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __,SUBSYS_ENTRY_POINT_NAME)(__VA_ARGS__,\
                                                                                                                                  va_list arg,              \
                                                                                                                                  void(*fn_ptr)(__VA_ARGS__,\
                                                                                                                                      va_list arg));        \
                                                                                                                                                            \
        typedef void(*SUBSYS_ENTRY_POINT_NAME##_fn_t)(__VA_ARGS__);                                                                                         \
        static inline __attribute__ ((__gnu_inline__))                                                                                                      \
                void _##SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) SUBSYS_ENTRY_POINT_NAME##_fn_t fn_ptr, size_t num_var_args, ...){                 \
            va_list args, args_copy;                                                                                                                        \
                                                                                                                                                            \
            va_start(args, num_var_args);                                                                                                                   \
                                                                                                                                                            \
            args_copy = skadi_valist_clone(args, num_var_args, false);                                                                                      \
            CONCAT(__skadi_caller_trampoline_fn_ptr_va_void_allow_self__, SKADI_SUBSYSTEM_COUNT_NUM_USED_REGS(__VA_ARGS__), __,SUBSYS_ENTRY_POINT_NAME)(    \
                                                                                                ARG_NAMES_WITHOUT_TYPE, args_copy, fn_ptr);                 \
                                                                                                                                                            \
            skadi_cloned_valist_free(args_copy);                                                                                                            \
                                                                                                                                                            \
            va_end(args);                                                                                                                                   \
                                                                                                                                                            \
        }	                                                                                                                                                \
                                                                                                                                                            \
        static inline __attribute__ ((__gnu_inline__)) void SUBSYS_ENTRY_POINT_NAME(__VA_ARGS__ __VA_OPT__(,) SUBSYS_ENTRY_POINT_NAME##_fn_t fn_ptr, ...){  \
            size_t num_var_args = __builtin_va_arg_pack_len();                                                                                              \
                                                                                                                                                            \
            _##SUBSYS_ENTRY_POINT_NAME(ARG_NAMES_WITHOUT_TYPE, fn_ptr, num_var_args, __builtin_va_arg_pack());                                              \
        }

    /* currently not needed */
    #define SKADI_SUBSYSTEM_INITIALIZE_CALLER_TRAMPOLINE(SUBSYS_ENTRY_POINT_NAME) true

    #define SKADI_SUBSYSTEM_INIT_FUNCTIONS(...) static const void *const init_fn_ptrs[] __used Z_GENERIC_SECTION(".init_array") = {     \
        __VA_ARGS__                                                                                                                     \
    };

    #define SKADI_SUBSYSTEM_FINI_FUNCTIONS(...) static const void *const fini_fn_ptrs[] __used Z_GENERIC_SECTION(".fini_array") = {     \
        __VA_ARGS__                                                                                                                     \
    };


    #define SKADI_SUBSYSTEM_INIT_RETURN(VAR)                        \
        __asm__ volatile (                                          \
            SKADI_SUBSYSTEM_FLUSH_BRANCH_TARGET_PREDICTION          \
        );                                                          \
        return VAR;

    /* register width */
    #define SKADI_VALIST_SIZE(NUMBER_ELEMENTS) ((NUMBER_ELEMENTS) * sizeof(uintptr_t))

    static inline va_list skadi_valist_clone(va_list list, size_t number_elements, bool writable){
        va_list copy;
        /* derive with length zero is not allowed */
        if(!number_elements){
            return NULL;
        }
        if(writable){
            copy = (va_list) skadi_cap_ops_derive_arg(list, SKADI_VALIST_SIZE(number_elements));
        }
        else{
            copy = (va_list) skadi_cap_ops_derive_arg_ro(list, SKADI_VALIST_SIZE(number_elements));
        }
        return copy ? copy : list;
    }
    static inline void skadi_cloned_valist_free(va_list list){
        skadi_cap_ops_drop(list);
    }

    static inline bool skadi_token_is_in_our_text(void* token){
        skadi_inspect_metadata_t inspect_metadata;
        bool ret;
    
        ret = skadi_cap_ops_inspect(token, &inspect_metadata);
    
        __ASSERT_NO_MSG(ret);
    
        if(!ret){
            return false;
        }
    
        if(!inspect_metadata.execute_permission){
            return false;
        }
    
        if(inspect_metadata.restriction_type == SKADI_RESTRICTIONS_NONE || inspect_metadata.restriction_type == SKADI_RESRICTIONS_DEVICE_INTERPRETED){
            return true;
        }
    
        /* task-id bound, task-id-set */
        return inspect_metadata.restriction_body.task_restriction.restriction_task_id == SKADI_CURRENT_TASK_ID && inspect_metadata.restriction_body.task_restriction.restriction_device_id == SKADI_DEVICE_ID_CPU;
    
    }    
#endif
/* to make sure defined symbols are included */
#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_irq.h>
