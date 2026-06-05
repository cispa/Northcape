#ifndef SKADI_EVENT_H
#define SKADI_EVENT_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_event_init, struct k_event *event);

#define SKADI_EVENT_ASSERT(EVENT, FILE, LINE)                      \
    __ASSERT(EVENT, "Uninitialized event at %s:%d", FILE, LINE)

static inline void __skadi_event_init_wrapper(struct k_event *event, const char *file, int line){
    SKADI_EVENT_ASSERT(event, file, line);

    __skadi_event_init(event);
}

#define skadi_event_init(event)                               \
    __skadi_event_init_wrapper(event, __FILE__, __LINE__)     \
    


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_event_post, struct k_event *event, uint32_t events);

static inline uint32_t _skadi_event_post(struct k_event *event, uint32_t events, const char *file, int line){
    SKADI_EVENT_ASSERT(event, file, line);

    return __skadi_event_post(event, events);
}

#define skadi_event_post(event, events)                  \
    _skadi_event_post(event, events, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_event_set, struct k_event *event, uint32_t events);

static inline uint32_t _skadi_event_set(struct k_event *event, uint32_t events, const char *file, int line){
    SKADI_EVENT_ASSERT(event, file, line);

    return __skadi_event_set(event, events);
}

#define skadi_event_set(event, events)                  \
    _skadi_event_set(event, events, __FILE__, __LINE__)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_event_set_masked, struct k_event *event, uint32_t events, uint32_t events_masked);

static inline uint32_t _skadi_event_set_masked(struct k_event *event, uint32_t events, uint32_t events_masked, const char *file, int line){
    SKADI_EVENT_ASSERT(event, file, line);

    return __skadi_event_set_masked(event, events, events_masked);
}
    
#define skadi_event_set_masked(event, events, events_masked)   \
    _skadi_event_set_masked(event, events, events_masked __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_event_clear, struct k_event *event, uint32_t events);

static inline uint32_t _skadi_event_clear(struct k_event *event, uint32_t events, const char *file, int line){
    SKADI_EVENT_ASSERT(event, file, line);

    return __skadi_event_clear(event, events);
}

#define skadi_event_clear(event, events)                  \
    _skadi_event_clear(event, events, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_event_wait, struct k_event *event, uint32_t events, bool reset, k_timeout_t timeout);

static inline uint32_t _skadi_event_wait(struct k_event *event, uint32_t events, bool reset, k_timeout_t timeout, const char *file, int line){
    SKADI_EVENT_ASSERT(event, file, line);

    return __skadi_event_wait(event, events, reset, timeout);
}

#define skadi_event_wait(event, events, reset, timeout)                  \
    _skadi_event_wait(event, events, reset, timeout, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uint32_t, __skadi_event_wait_all, struct k_event *event, uint32_t events, bool reset, k_timeout_t timeout);

static inline uint32_t _skadi_event_wait_all(struct k_event *event, uint32_t events, bool reset, k_timeout_t timeout, const char *file, int line){
    SKADI_EVENT_ASSERT(event, file, line);

    return __skadi_event_wait_all(event, events, reset, timeout);
}

#define skadi_event_wait_all(event, events, reset, timeout)                  \
    _skadi_event_wait_all(event, events, reset, timeout, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_event_cleanup, struct k_event *event);
#define skadi_event_cleanup(event) __skadi_event_cleanup(event)

#endif /* SKADI_SUBSYSTEM */

extern void skadi_subsystem_yield(void);
#endif /* SKADI_EVENT_H */
