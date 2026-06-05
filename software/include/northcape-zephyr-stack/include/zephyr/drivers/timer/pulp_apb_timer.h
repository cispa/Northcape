#ifndef ZEPHYR_INCLUDE_DRIVERS_TIMER_PULP_APB_TIMER_H__
#define ZEPHYR_INCLUDE_DRIVERS_TIMER_PULP_APB_TIMER_H__

typedef bool (*pulp_apb_timer_callback_t)(const struct device *dev, uint32_t current_time, void *cookie);

extern const struct device *pulp_apb_timer_get_first_device(void);

extern uint32_t pulp_apb_timer_get_current_time(const struct device *dev);

extern void pulp_apb_timer_schedule_compare_callback(const struct device *dev, uint32_t compare_time, pulp_apb_timer_callback_t callback, void *cookie);

extern void pulp_apb_timer_set_time(const struct device *dev, uint32_t time);

extern uint64_t pulp_apb_timer_time_to_ns(const struct device *dev, uint32_t time);

extern uint32_t pulp_apb_timer_ns_to_cycles(const struct device *dev, uint64_t time_ns);

#endif
