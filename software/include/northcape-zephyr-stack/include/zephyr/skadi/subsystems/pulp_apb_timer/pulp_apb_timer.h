#ifndef ZEPHYR_INCLUDE_DRIVERS_TIMER_PULP_APB_TIMER_H
#define ZEPHYR_INCLUDE_DRIVERS_TIMER_PULP_APB_TIMER_H

#include <stdbool.h>
#include <stdint.h>
#include <zephyr/device.h>

#include <zephyr/skadi/skadi_subsystem.h>

typedef bool (*pulp_apb_timer_callback_t)(const struct device *dev, uint32_t current_time, void *cookie);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(const struct device *, pulp_apb_timer_get_first_device, void);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, pulp_apb_timer_get_current_time, const struct device *dev);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(pulp_apb_timer_schedule_compare_callback, const struct device *dev, uint32_t compare_time, pulp_apb_timer_callback_t callback, void *cookie);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(pulp_apb_timer_set_time, const struct device *dev, uint32_t time);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint64_t, pulp_apb_timer_time_to_ns, const struct device *dev, uint32_t time);

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, pulp_apb_timer_ns_to_cycles, const struct device *dev, uint64_t time_ns);

#endif
