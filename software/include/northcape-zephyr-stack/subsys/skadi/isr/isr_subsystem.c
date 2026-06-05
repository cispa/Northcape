#include <zephyr/logging/log.h>

#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_loader.h>

#include <zephyr/kernel.h>

#include <zephyr/kernel_structs.h>
#include <zephyr/sw_isr_table.h>
#include <zephyr/arch/cpu.h>

// z_check_stack_sentinel
#include <kswap.h>
// z_get_next_switch_handle
#include <ksched.h>

LOG_MODULE_REGISTER(skadi_isr_subsystem, CONFIG_SKADI_SUBSYSTEM_LOG_LEVEL);

#include <zephyr/skadi/skadi_sched.h>


struct skadi_subsystem_stack *isr_stack;
#ifdef CONFIG_SKADI_DEBUG
uint64_t skadi_isr_level;
#endif

/**
 * Registered ISR handlers by cause.
 * Set using subsystem call.
 * Shares the format with the normal zephyr table for ease of use in ISR code.
 */
struct _isr_table_entry __sw_isr_table skadi_isr_table[IRQ_TABLE_SIZE] = {0};

static uint32_t skadi_isr_subsystem_task_id = 0;

extern void _skadi_isr_wrapper_callee_trampoline(void);
extern void _skadi_isr_wrapper_callee_trampoline_end(void);
EXPORT_SYMBOL(_skadi_isr_wrapper_callee_trampoline);
EXPORT_SYMBOL(_skadi_isr_wrapper_callee_trampoline_end);

/* initializes the actual jump address in the trampoline */
extern void _skadi_isr_wrapper_callee_trampoline_init(void);


// "near" wrappers for imported functions
void skadi_check_stack_sentinel(void){
    z_check_stack_sentinel();
}


// TODO when we are calling this with subsystem calling convention, need to be sure that we have stack etc.
static void unregistered_irq(const void *param){
    __asm__ volatile(
        "csrwi mie, 0x0"
    );
    // TODO printing the number causes spurious bus error for some reason
    LOG_ERR("Spurious IRQ");
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(isr_stub, const void*);

static bool is_in_isr;

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(skadi_trigger_immediate_timer_interrupt, void);

void skadi_isr_wrap_subsystem_call(const void *arg, void (*isr)(const void *arg)){
    is_in_isr = true;
    LOG_DBG("Processing IRQ!\n");

    if(isr == unregistered_irq){
        LOG_INF("Going into unregistered IRQ!\n");
        // can call in normal calling convention
        unregistered_irq(arg);
    }
    else{
        LOG_DBG("Going into registered IRQ!\n");
        // subsystem call into registered handler token
        isr_stub(arg, isr);
    }

    /* check if we need to reschedule to service the interrupt */
    skadi_trigger_immediate_timer_interrupt();

    is_in_isr = false;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(bool, skadi_is_in_isr, void)
	return is_in_isr;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_is_in_isr)



SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(bool, skadi_isr_register_handler, const int irq_number, const void *arg, void (*isr)(const void *arg))
{
    if(irq_number >= IRQ_TABLE_SIZE){
        LOG_ERR("IRQ number is too big!");
        return false;
    }

    if(!skadi_subsystem_can_accept_function_pointer((uintptr_t)isr, NULL, skadi_isr_subsystem_task_id, false, false)){
        LOG_ERR("Function pointer unacceptable!");
        return false;
    }

    skadi_isr_table[irq_number].isr = isr;
    skadi_isr_table[irq_number].arg = arg;

    LOG_INF("Registered IRQ handler!");

    return true;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_isr_register_handler)

/* timer scheduler hook location + relocation for the ISR */
extern uint64_t skadi_isr_timer_sched_hook_reloc;
extern void (**skadi_subsystem_mtimer_sched_hook)(void);

static bool skadi_isr_init(void){
    skadi_task_id_t my_task_id = SKADI_CURRENT_TASK_ID;
    SKADI_INSTALL_TIME_INTERRUPT_HOOK;
    
    _skadi_isr_wrapper_callee_trampoline_init();

    skadi_isr_timer_sched_hook_reloc = (uint64_t) skadi_subsystem_mtimer_sched_hook;

    skadi_isr_subsystem_task_id = my_task_id;
    
    isr_stack = (struct skadi_subsystem_stack *) skadi_allocator_alloc_rw(sizeof(*isr_stack));

    __ASSERT_NO_MSG(isr_stack);

    if(!isr_stack){
        return false;
    }

    isr_stack = (struct skadi_subsystem_stack *) skadi_subsystem_prepare_allocated_stack(isr_stack, SKADI_CURRENT_TASK_ID, NULL);

    for(int i = 0; i < IRQ_TABLE_SIZE; i++){
        skadi_isr_table[i].isr = unregistered_irq;
        skadi_isr_table[i].arg = (void *)(uintptr_t) i;
    }

	return true;
}
/* we need to initialize the ISR subsystem as soon as the subsystem is loaded */
/* the loader will make it active immediately after loading it */
SKADI_SUBSYSTEM_INIT_FUNCTIONS(skadi_isr_init);
