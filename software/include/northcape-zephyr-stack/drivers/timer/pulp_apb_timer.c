#include <zephyr/device.h>
#include <zephyr/logging/log.h>
#include <zephyr/irq.h>
#include <zephyr/sys/barrier.h>
#include <zephyr/sys/sys_io.h>
#include <zephyr/sys/util.h>
#include <zephyr/llext/symbol.h>
#include <zephyr/llext/llext.h>

#ifdef CONFIG_SKADI_LOADER
#include <zephyr/skadi/skadi_ops_driver.h>

#include <zephyr/skadi/subsystems/pulp_apb_timer/pulp_apb_timer.h>

#include <zephyr/skadi/skadi_subsystem.h>

#include <zephyr/skadi/skadi_irq.h>
#include <zephyr/skadi/skadi_device.h>

#include <zephyr/skadi/skadi_sched.h>
#else
#include <zephyr/drivers/timer/pulp_apb_timer.h>
#endif

LOG_MODULE_REGISTER(pulp_apb_timer, CONFIG_LOG_DEFAULT_LEVEL);

#define PULP_APB_TIMER_REGISTER_OFFSET_TIME 0
#define PULP_APB_TIMER_REGISTER_OFFSET_CTRL 1
#define PULP_APB_TIMER_REGISTER_OFFSET_CMP  2

#define PULP_APB_TIMER_ENABLE_MASK BIT(0)
#define PULP_APB_TIMER_DISABLE_MASK 0

#define PULP_APB_TIMER_CHANNEL_OVERFLOW 0
#define PULP_APB_TIMER_CHANNEL_MATCH 1

#define DT_DRV_COMPAT pulp_apb_timer

struct pulp_apb_timer_config {
	void *reg;
	/* this should always be 2 - one for overflow, one for compare */
	uint32_t channels;
	void (*irq_configure)(void);
	uint32_t *irq0_channels;
	size_t irq0_channels_size;
	uint32_t clock_period_ns;
};

#ifdef CONFIG_SKADI_LOADER
const static struct device *skadi_get_own_device_representation(const struct device *dev);
#endif

struct pulp_apb_timer_channel {
    pulp_apb_timer_callback_t callback;
    void *cookie;
	bool callback_is_capability;
};

__asm__(
    "pulp_apb_timer_store_32:\n\r"
    "sw a0, 0(a1)\n\r"
    "ret\n"
);

extern void pulp_apb_timer_store_32(uint32_t value, mem_addr_t addr);

/* global state for device and array of per-channel states */
struct pulp_apb_timer_data {
	struct pulp_apb_timer_channel *channels;
};

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(const struct device *,pulp_apb_timer_get_first_device, void)
#else
const struct device *pulp_apb_timer_get_first_device(void)
#endif
{
	return DEVICE_DT_GET(DT_NODELABEL(pulp_timer));
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(pulp_apb_timer_get_first_device)
#endif

static inline uint64_t __pulp_apb_timer_time_to_ns(const struct device *dev, uint32_t time){
	const struct pulp_apb_timer_config *cfg = dev->config;
	return ((uint64_t) time) * cfg->clock_period_ns;
}

static inline uint32_t __pulp_apb_timer_ns_to_cycles(const struct device *dev, uint64_t time_ns){
	const struct pulp_apb_timer_config *cfg = dev->config;
	return (uint32_t)((time_ns) / cfg->clock_period_ns);
}

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(uint64_t,pulp_apb_timer_time_to_ns, const struct device *dev, uint32_t time){
	dev = skadi_get_own_device_representation(dev);
#else
uint64_t pulp_apb_timer_time_to_ns(const struct device *dev, uint32_t time){
#endif
	return __pulp_apb_timer_time_to_ns(dev, time);
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(pulp_apb_timer_time_to_ns)
#endif

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(uint32_t,pulp_apb_timer_ns_to_cycles, const struct device *dev, uint64_t time){
	dev = skadi_get_own_device_representation(dev);
#else
uint32_t pulp_apb_timer_ns_to_cycles(const struct device *dev, uint64_t time){
#endif
	return __pulp_apb_timer_ns_to_cycles(dev, time);
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(pulp_apb_timer_ns_to_cycles)
#endif


static inline uint32_t __pulp_apb_timer_get_current_time(const struct device *dev){
	const struct pulp_apb_timer_config *cfg = dev->config;
    const uint32_t *reg_intf = cfg -> reg;

    reg_intf += PULP_APB_TIMER_REGISTER_OFFSET_TIME;

    return sys_read32((mem_addr_t)reg_intf);
}

static inline void __pulp_apb_timer_set_time(const struct device *dev, uint32_t time){
	const struct pulp_apb_timer_config *cfg = dev->config;
    const uint32_t *reg_intf = cfg -> reg;

    reg_intf += PULP_APB_TIMER_REGISTER_OFFSET_TIME;

	pulp_apb_timer_store_32(time, (mem_addr_t)reg_intf);
}

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void,pulp_apb_timer_set_time, const struct device *dev, uint32_t time)
	dev = skadi_get_own_device_representation(dev);
#else
void pulp_apb_timer_set_time(const struct device *dev, uint32_t time)
#endif
{
	__pulp_apb_timer_set_time(dev, time);
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(pulp_apb_timer_set_time)
#endif

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(uint32_t,pulp_apb_timer_get_current_time, const struct device *dev)
	dev = skadi_get_own_device_representation(dev);
#else
uint32_t pulp_apb_timer_get_current_time(const struct device *dev)
#endif
{
    return __pulp_apb_timer_get_current_time(dev);
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(pulp_apb_timer_get_current_time)
#endif

static inline void __pulp_apb_timer_schedule_compare_callback(const struct device *dev, uint32_t compare_time, pulp_apb_timer_callback_t callback, void *cookie){
	const struct pulp_apb_timer_config *cfg = dev->config;
	struct pulp_apb_timer_data *data = dev->data;
	struct pulp_apb_timer_channel *channel_data = &data->channels[PULP_APB_TIMER_CHANNEL_MATCH];
    const uint32_t *reg_intf = cfg -> reg;

	LOG_DBG("Scheduling callback at %u!",compare_time);

    channel_data -> callback = callback;
    channel_data -> cookie = cookie;
    
    pulp_apb_timer_store_32(PULP_APB_TIMER_ENABLE_MASK, (mem_addr_t)(reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CTRL));

	pulp_apb_timer_store_32(compare_time, (mem_addr_t)(reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CMP));

	LOG_DBG("Scheduled callback at %"PRIu32, compare_time);
}

// re-enabling IRQ at this time might cause us to service the interrupt in case this was called from its ISR
// this can cause an infinite loop
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, pulp_apb_timer_schedule_compare_callback, const struct device *dev, uint32_t compare_time, pulp_apb_timer_callback_t callback, void *cookie)
	dev = skadi_get_own_device_representation(dev);
#else
void pulp_apb_timer_schedule_compare_callback(const struct device *dev, uint32_t compare_time, pulp_apb_timer_callback_t callback, void *cookie)
#endif
{
	struct pulp_apb_timer_data *data = dev->data;
	struct pulp_apb_timer_channel *channel_data = &data->channels[PULP_APB_TIMER_CHANNEL_MATCH];
	channel_data->callback_is_capability = true;
    __pulp_apb_timer_schedule_compare_callback(dev, compare_time, callback, cookie);
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(pulp_apb_timer_schedule_compare_callback)
#endif

static void pulp_apb_timer_overflow_isr(const struct device *dev){
	const struct pulp_apb_timer_config *cfg = dev->config;
    const uint32_t *reg_intf = cfg -> reg;

    LOG_WRN("Timer overflow!");
	// acknowledge interrupt to device
	pulp_apb_timer_store_32(PULP_APB_TIMER_DISABLE_MASK, (mem_addr_t)(reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CTRL));
}


#ifdef CONFIG_SKADI_LOADER
SKADI_GENERATE_IRQ_HANDLER_WRAPPER(pulp_apb_timer_overflow_isr)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(bool, callback_stub, const struct device *, uint32_t, void*);
#endif

static void pulp_apb_timer_compare_isr(const struct device *dev){
    const struct pulp_apb_timer_config *cfg = dev->config;
	struct pulp_apb_timer_data *data = dev->data;
	struct pulp_apb_timer_channel *channel_data = &data->channels[PULP_APB_TIMER_CHANNEL_MATCH];
    const uint32_t *reg_intf = cfg -> reg;

	LOG_DBG("Received compare interrupt - jumping into callback!");

    // acknowledge interrupt to device
    pulp_apb_timer_store_32(0, (mem_addr_t)(reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CMP));
    
    if(!channel_data->callback){
        LOG_WRN("Timer matched but no callback registered!");
    }
    else{
        bool continue_enable;
#ifdef CONFIG_SKADI_LOADER
		if(channel_data->callback_is_capability){
			skadi_subsystem_check_function_pointer(channel_data->callback, true, false);
			continue_enable = callback_stub(dev, __pulp_apb_timer_get_current_time(dev), channel_data -> cookie, channel_data->callback);
		}
		else{
#endif
		continue_enable = channel_data->callback(dev, __pulp_apb_timer_get_current_time(dev), channel_data -> cookie);

#ifdef CONFIG_SKADI_LOADER
		}
#endif
		

        if(continue_enable){
            pulp_apb_timer_store_32(PULP_APB_TIMER_ENABLE_MASK, (mem_addr_t)(reg_intf + PULP_APB_TIMER_REGISTER_OFFSET_CTRL));
        }

		LOG_DBG("Callback complete!");
	}
}


#ifdef CONFIG_SKADI_LOADER
SKADI_GENERATE_IRQ_HANDLER_WRAPPER(pulp_apb_timer_compare_isr)
#endif

static int pulp_apb_timer_init(const struct device *dev){
    const struct pulp_apb_timer_config *cfg = dev->config;

	cfg->irq_configure();
	return 0;
}


#if defined(CONFIG_IRQ_OFFLOAD) && defined(CONFIG_SKADI_OS)
/* we can use the APB timer to trigger an immediate timer interrupt */

static struct k_spinlock irq_offload_spinlock;

static irq_offload_routine_t offloaded_function;
static const void *offloaded_function_arg;

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(call_offloaded_function, const void *arg);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(skadi_trigger_immediate_timer_interrupt, void);

static bool pulp_apb_timer_call_irq_offload(const struct device *dev, const uint32_t time, void *arg){
	__ASSERT_NO_MSG(offloaded_function);
	LOG_DBG("IRQ offload called!\n");
    call_offloaded_function(offloaded_function_arg, offloaded_function);
	LOG_DBG("IRQ offload done!\n");
	/* this stops the device from interrupting again, as cmp=0 means disable*/
	__pulp_apb_timer_schedule_compare_callback(dev, 0, pulp_apb_timer_call_irq_offload, NULL);

	return false;
}

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, __skadi_irq_offload, irq_offload_routine_t routine, const void *parameter);
	/* mutual exclusion to protect ourselves */
	k_spinlock_key_t spinlock_key = k_spin_lock(&irq_offload_spinlock);
	const struct device *dev = DEVICE_DT_GET(DT_NODELABEL(pulp_timer));
	struct pulp_apb_timer_data *data = dev->data;
	struct pulp_apb_timer_channel *channel_data = &data->channels[PULP_APB_TIMER_CHANNEL_MATCH];
	/* need a thin wrapper */
	channel_data->callback_is_capability = false;

	offloaded_function = routine;
	offloaded_function_arg = parameter;
	/* cmp=0 would mean disable */
	__pulp_apb_timer_schedule_compare_callback(dev, 1, pulp_apb_timer_call_irq_offload, (void*)parameter);

    k_spin_unlock(&irq_offload_spinlock, spinlock_key);
	/* reschedule if necessary */
	skadi_yield();
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_irq_offload)
#endif

#ifdef CONFIG_SKADI_LOADER
/* first IRQ is overflow */
#define OVERFLOW_IRQ_CONFIGURE(inst)                                                                     \
	LOG_INF("Registering overflow interrupt handler %p!", SKADI_IRQ_HANDLER_FUNCTION_POINTER(inst, pulp_apb_timer_overflow_isr));	\
		if(skadi_register_interrupt_handler(DT_INST_IRQN_BY_IDX(inst, 0), NULL, SKADI_IRQ_HANDLER_FUNCTION_POINTER(inst, pulp_apb_timer_overflow_isr)) == false){	\
			LOG_ERR("Could not register overflow ISR handler!");																							\
		}																																		\
		LOG_INF("Registered overflow interrupt handler!");	\
	skadi_irq_enable(DT_INST_IRQN_BY_IDX(inst, 0), SKADI_IRQ_PRIORITY_DEFAULT);

/* second IRQ is compare match */
#define COMPARE_IRQ_CONFIGURE(inst)                                                                     \
	LOG_INF("Registering compare interrupt handler %p!", SKADI_IRQ_HANDLER_FUNCTION_POINTER(inst, pulp_apb_timer_compare_isr));	\
		if(skadi_register_interrupt_handler(DT_INST_IRQN_BY_IDX(inst, 1), NULL, SKADI_IRQ_HANDLER_FUNCTION_POINTER(inst, pulp_apb_timer_compare_isr)) == false){	\
			LOG_ERR("Could not register compare ISR handler!");																							\
		}																																		\
	LOG_INF("Registered compare interrupt handler!");	\
	skadi_irq_enable(DT_INST_IRQN_BY_IDX(inst, 1), SKADI_IRQ_PRIORITY_DEFAULT);

#else
/* first IRQ is overflow */
#define OVERFLOW_IRQ_CONFIGURE(inst)                                                                     \
		IRQ_CONNECT(DT_INST_IRQN_BY_IDX(inst, 0), DT_INST_IRQ_BY_IDX(inst, 0, priority), pulp_apb_timer_overflow_isr, DEVICE_DT_INST_GET(inst), 0);	\
		irq_enable(DT_INST_IRQN_BY_IDX(inst, 0));

/* second IRQ is compare match */
#define COMPARE_IRQ_CONFIGURE(inst)                                                                     \
		IRQ_CONNECT(DT_INST_IRQN_BY_IDX(inst, 1), DT_INST_IRQ_BY_IDX(inst, 1, priority), pulp_apb_timer_compare_isr, DEVICE_DT_INST_GET(inst), 0);	\
		irq_enable(DT_INST_IRQN_BY_IDX(inst, 1));
#endif
	
#define CONFIGURE_ALL_IRQS(inst)                                                                   \
	LOG_INF("Configuring IRQs %u and %u!",DT_INST_IRQN_BY_IDX(inst, 0), DT_INST_IRQN_BY_IDX(inst, 1)); \
	OVERFLOW_IRQ_CONFIGURE(inst);                                                                    \
	COMPARE_IRQ_CONFIGURE(inst);

#define PULP_APB_TIMER_INIT(inst)                                                                  \
	static void pulp_apb_timer##inst##_irq_configure(void)                                 \
	{                                                                                          \
		CONFIGURE_ALL_IRQS(inst);                                                          \
	}                                                                                          \
	static uint32_t pulp_apb_timer##inst##_irq0_channels[] =                               \
		DT_INST_PROP_OR(inst, interrupts, {0});                                            \
	static const struct pulp_apb_timer_config pulp_apb_timer##inst##_config = {        \
		.reg = (void *)(uintptr_t)DT_INST_REG_ADDR(inst),                                  \
		.channels = 2,  /* overflow and compare */                                    \
		.irq_configure = pulp_apb_timer##inst##_irq_configure,                         \
		.irq0_channels = pulp_apb_timer##inst##_irq0_channels,                         \
		.irq0_channels_size = ARRAY_SIZE(pulp_apb_timer##inst##_irq0_channels),        \
		.clock_period_ns = DT_INST_PROP(inst, pulp_clock_period_ns)						\
	};                                                                                         \
	static struct pulp_apb_timer_channel                                                   \
		pulp_apb_timer##inst##_channels[2];             \
	ATOMIC_DEFINE(pulp_apb_timer_atomic##inst, 2);          \
	static struct pulp_apb_timer_data pulp_apb_timer##inst##_data = {                  \
		.channels = pulp_apb_timer##inst##_channels,                                   \
	};                                                                                         \
                                                                                                   \
	DEVICE_DT_INST_DEFINE(inst, &pulp_apb_timer_init, NULL,                                \
			      &pulp_apb_timer##inst##_data,                                    \
			      &pulp_apb_timer##inst##_config, POST_KERNEL,                     \
			      CONFIG_PULP_APB_TIMER_INIT_PRIORITY, NULL);



DT_INST_FOREACH_STATUS_OKAY(PULP_APB_TIMER_INIT)

#ifdef CONFIG_SKADI_LOADER
const static struct device *skadi_get_own_device_representation(const struct device *dev){
    const struct device *ret = NULL;
	const int device_node_id = device_get_dt_id(dev);


	SKADI_GET_OWN_DEVICE_REPRESENTATION(device_node_id)

    __ASSERT(ret != NULL, "should be able to resolve the device I was given by other subsystem");

    return ret;
}
#endif
