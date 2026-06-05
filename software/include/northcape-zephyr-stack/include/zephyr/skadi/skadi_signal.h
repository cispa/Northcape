#ifndef SKADI_SIGNAL_H
#define SKADI_SIGNAL_H

#include <zephyr/kernel.h>
#include <zephyr/skadi/skadi_subsystem.h>

#ifdef SKADI_SUBSYSTEM
/* in the loader, use the z_impl_* variants directly */

#define SKADI_SIGNAL_ASSERT(SIG, FILE, LINE)                                            \
    __ASSERT(SIG, "Signal is null at %s:%d", FILE, LINE)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_poll_signal_init, struct k_poll_signal *sig);

static inline int _skadi_poll_signal_init(struct k_poll_signal *sig, const char *file, const int line){
    SKADI_SIGNAL_ASSERT(sig, file, line);

    return  __skadi_poll_signal_init(sig);
}

#define skadi_poll_signal_init(SIGNAL) _skadi_poll_signal_init(SIGNAL, __FILE__, __LINE__)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_poll_signal_raise, struct k_poll_signal *sig, int result);

static inline int _skadi_poll_signal_raise(struct k_poll_signal *sig, int result, const char *file, const int line){
    SKADI_SIGNAL_ASSERT(sig, file, line);
    return __skadi_poll_signal_raise(sig, result);
}

#define skadi_poll_signal_raise(SIGNAL, RESULT) _skadi_poll_signal_raise(SIGNAL, RESULT, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_poll_signal_check, struct k_poll_signal *sig, unsigned int *signaled, int *result);

static inline void _skadi_poll_signal_check(struct k_poll_signal *sig, unsigned int *signaled, int *result, const char *file, const int line){
    SKADI_SIGNAL_ASSERT(sig, file, line);
    unsigned int *signaled_token = skadi_cap_ops_derive_arg_wo(signaled, sizeof(*signaled));
    unsigned int *result_token = skadi_cap_ops_derive_arg_wo(result, sizeof(*result));

    __ASSERT_NO_MSG(signaled_token);
    __ASSERT_NO_MSG(result_token);

    if(!signaled_token || !result_token){
        goto out;
    }
    __skadi_poll_signal_check(sig, signaled_token, result_token);

    out:
    if(signaled_token){
        skadi_cap_ops_drop(signaled_token);
    }
    if(result_token){
        skadi_cap_ops_drop(result_token);
    }
}

#define skadi_poll_signal_check(SIGNAL, SIGNALED, RESULT) _skadi_poll_signal_check(SIGNAL, SIGNALED, RESULT, __FILE__, __LINE__)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_poll_signal_reset, struct k_poll_signal *sig);

static inline void _skadi_poll_signal_reset(struct k_poll_signal *sig, const char *file, const int line){
    SKADI_SIGNAL_ASSERT(sig, file, line);
    __skadi_poll_signal_reset(sig);
}

#define skadi_poll_signal_reset(SIGNAL) _skadi_poll_signal_reset(SIGNAL, __FILE__, __LINE__)


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_poll, struct k_poll_event *events, int num_events, k_timeout_t timeout);

static inline int _skadi_poll(struct k_poll_event *events, int num_events, k_timeout_t timeout, const char *file, const int line){
    struct k_poll_event *events_token = num_events ? skadi_cap_ops_derive_arg(events, sizeof(*events)*num_events) : events;
    int ret;
    __ASSERT_NO_MSG(events);
    __ASSERT_NO_MSG(events_token);
    if(!events_token){
        return -ENOMEM;
    }
    ret = __skadi_poll(events_token, num_events, timeout);

    if(events_token != events){
        skadi_cap_ops_drop(events_token);
    }
    
    return ret;
}

#define skadi_poll(EVENTS, NUM_EVENTS, TIMEOUT) _skadi_poll(EVENTS, NUM_EVENTS, TIMEOUT, __FILE__, __LINE__)

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_poll_signal_cleanup, struct k_poll_signal *sig);
static inline void skadi_poll_signal_cleanup(struct k_poll_signal *sig){
    __skadi_poll_signal_cleanup(sig);
}

/* inlined from poll.c */
static inline void skadi_poll_event_init(struct k_poll_event *event, uint32_t type, int mode, void *obj){
    __ASSERT(mode == K_POLL_MODE_NOTIFY_ONLY,
		 "only NOTIFY_ONLY mode is supported\n");
	__ASSERT(type < (BIT(_POLL_NUM_TYPES)), "invalid type\n");
	__ASSERT(obj != NULL, "must provide an object\n");

	event->poller = NULL;
	/* event->tag is left uninitialized: the user will set it if needed */
	event->type = type;
	event->state = K_POLL_STATE_NOT_READY;
	event->mode = mode;
	event->unused = 0U;
	event->obj = obj;

	SYS_PORT_TRACING_FUNC(k_poll_api, event_init, event);
}

#endif /* SKADI_SUBSYSTEM */

#endif /* SKADI_SIGNAL_H */
