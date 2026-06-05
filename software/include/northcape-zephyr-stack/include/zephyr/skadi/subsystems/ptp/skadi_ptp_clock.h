#ifndef SKADI_PTP_CLOCK_H
#define SKADI_PTP_CLOCK_H
#include <zephyr/device.h>
#include <zephyr/drivers/ptp_clock.h>
#include <zephyr/skadi/skadi_subsystem.h>


/* function pointer wrappers for API functions */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, __skadi_ptp_clock_get, const struct device *dev, struct net_ptp_time *tm);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, __skadi_ptp_clock_set, const struct device *dev, struct net_ptp_time *tm);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, __skadi_ptp_clock_adjust, const struct device *dev, int increment);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, __skadi_ptp_clock_rate_adjust, const struct device *dev, double ratio);

static inline int skadi_ptp_clock_get(const struct device *dev, struct net_ptp_time *tm)
{
    const struct ptp_clock_driver_api *api =
        (const struct ptp_clock_driver_api *)dev->api;
    struct net_ptp_time *tm_token = skadi_cap_ops_derive_arg_wo(tm, sizeof(*tm));
    int ret;

    __ASSERT_NO_MSG(tm_token);

    if(!tm_token){
        return -ENOMEM;
    }

    skadi_subsystem_check_function_pointer(api->get, true, false);

    ret = __skadi_ptp_clock_get(dev, tm_token, api->get);

    skadi_cap_ops_drop(tm_token);

    return ret;
}

static inline int skadi_ptp_clock_set(const struct device *dev, const struct net_ptp_time *tm)
{
    const struct ptp_clock_driver_api *api =
        (const struct ptp_clock_driver_api *)dev->api;
    struct net_ptp_time *tm_token = (void*) skadi_cap_ops_derive_arg_ro(tm, sizeof(*tm));
    int ret;

    __ASSERT_NO_MSG(tm_token);

    if(!tm_token){
        return -ENOMEM;
    }

    skadi_subsystem_check_function_pointer(api->set, true, false);

    ret = __skadi_ptp_clock_set(dev, tm_token, api->set);

    skadi_cap_ops_drop(tm_token);

    return ret;
}



#endif /* SKADI_PTP_CLOCK_H */
