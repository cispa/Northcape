#ifndef SKADI_DEVICE_H
#define SKADI_DEVICE_H

#include <zephyr/device.h>
#include <zephyr/skadi/skadi_subsystem.h>

#define SKADI_IRQ_HANDLER_WRAPPER_NAME(n,HANDLER_NAME) HANDLER_NAME##_wrapper##n
#define SKADI_IRQ_HANDLER_FUNCTION_POINTER(n,HANDLER_NAME) SKADI_SUBSYSTEM_FUNCTION_POINTER(HANDLER_NAME##_wrapper##n)

// we cannot pass the device pointer to/from the ISR subsystem, as we do not trust it
// if we did this, the ISR subsystem would not have any access to the functions / metadata in the device
// but it could change the token to anything it wants, possibly causing a problem
// thus, we determine the device based on the function we call
// IRQ handlers are also called via subsystem call, so we need to generate a callee trampoline
#define _SKADI_GENERATE_IRQ_HANDLER_WRAPPER(n,handler_name)								\
    SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, handler_name##_wrapper##n, const void *arg) \
    {                                                                                                                 \
        LOG_DBG("Received IRQ from ISR subsystem!");							\
        handler_name(&DEVICE_NAME_GET(Z_DEVICE_DT_DEV_ID(DT_DRV_INST(n))));	\
        LOG_DBG("Handling IRQ complete!");										\
    }   \
    SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(handler_name##_wrapper##n)    

#define SKADI_GENERATE_IRQ_HANDLER_WRAPPER(HANDLER_NAME) DT_INST_FOREACH_STATUS_OKAY_VARGS(_SKADI_GENERATE_IRQ_HANDLER_WRAPPER, HANDLER_NAME)

#define SKADI_DEVICE_INIT_CALL(n,INIT_FN)	 \
	INIT_FN(&DEVICE_NAME_GET(Z_DEVICE_DT_DEV_ID(DT_DRV_INST(n))));

#define SKADI_DEVICES_INIT(INIT_FN) DT_INST_FOREACH_STATUS_OKAY_VARGS(SKADI_DEVICE_INIT_CALL, INIT_FN)

#define _SKADI_CHECK_SAME_DEVICE(n,NODE_ID)                                                             \
    if(device_get_dt_id(&DEVICE_NAME_GET(Z_DEVICE_DT_DEV_ID(DT_DRV_INST(n)))) == NODE_ID) {                 \
        return &DEVICE_NAME_GET(Z_DEVICE_DT_DEV_ID(DT_DRV_INST(n)));                                        \
    }

/**
 * @brief Iterate through local devices, pick the first one with maching node ID.
 * Needs DT_DRV_COMPAT to be defined.
 */
#define SKADI_GET_OWN_DEVICE_REPRESENTATION(NODE_ID) DT_INST_FOREACH_STATUS_OKAY_VARGS(_SKADI_CHECK_SAME_DEVICE,NODE_ID)


#ifdef CONFIG_SKADI_OS
    /**
     * @brief Iterate through all devices defined in the device section and pick the one with matching node ID to the device I was given.
     */
    static inline const struct device* skadi_find_device_in_section(const struct device *dev){
        const int device_node_id = device_get_dt_id(dev);
        const struct device *ret = NULL;

        STRUCT_SECTION_FOREACH(device, cmp_dev){
            if(device_node_id != 0 && device_get_dt_id(cmp_dev) == device_node_id){
                return cmp_dev;
            }
        }

        __ASSERT(ret != NULL, "Assumed to find a device!");

        return ret;
    }
#define SKADI_DECLARE_DEVICE_REPRESENTATION_WRAPPER const static struct device *skadi_get_own_device_representation(const struct device *dev)

#define SKADI_GENERATE_DEVICE_REPRESENTATION_WRAPPER                                                                    \
    /**                                                                                                                 \
     * @brief Iterate through devices with DT_DRV_COMPAT compatibility and select the one with matching node ID.        \
     */                                                                                                                 \
    const static struct device *skadi_get_own_device_representation(const struct device *dev){                          \
        const struct device *ret = NULL;                                                                                \
        const int device_node_id = device_get_dt_id(dev);                                                               \
                                                                                                                        \
        SKADI_GET_OWN_DEVICE_REPRESENTATION(device_node_id)                                                             \
                                                                                                                        \
                                                                                                                        \
        __ASSERT(ret != NULL, "should be able to resolve the device I was given by other subsystem");                   \
                                                                                                                        \
        return ret;                                                                                                     \
    }

#else
#define SKADI_GENERATE_DEVICE_REPRESENTATION_WRAPPER                                                                    \
    const static struct device *skadi_get_own_device_representation(const struct device *dev){                          \
    /* one binary */                                                                                                    \
    return dev;                                                                                                         \
}                                                                                                                      

#endif

#ifdef CONFIG_SKADI_OS
    #define _SKADI_DEVICE_API_INIT(n)                                                                                   \
        dev_mut = (struct device *) &DEVICE_NAME_GET(Z_DEVICE_DT_DEV_ID(DT_DRV_INST(n)));                               \
                                                                                                                        \
        /* API itself is task-id-restricted */                                                                          \
        /* but the derived token is not */                                                                              \
        /* this allows everyone else to call us */                                                                      \
        dev_mut->api = (void *) derived_api;


    #define SKADI_DEVICES_API_INIT(API_STRUCT)                                                                          \
    {                                                                                                                   \
        /* this is called at initialization time - the device is still mutable */                                       \
	    struct device *dev_mut;                                                                                         \
	    skadi_restriction_t restriction = SKADI_NO_RESTRICTION;                                                         \
        void *derived_api;                                                                                              \
                                                                                                                        \
        if(skadi_cap_ops_derive(&API_STRUCT, restriction, sizeof(API_STRUCT),                                           \
           skadi_get_capability_offset(&API_STRUCT),SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE |           \
            SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,                                         \
            &derived_api) == false                                                                                      \
           || derived_api == 0){                                                                                        \
		    LOG_ERR("Could not derive token for API struct!");                                                          \
		    return false;                                                                                               \
        }                                                                                                               \
                                                                                                                        \
                                                                                                                        \
        DT_INST_FOREACH_STATUS_OKAY(_SKADI_DEVICE_API_INIT)                                                             \
                                                                                                                        \
                                                                                                                        \
    }
#endif

#endif
