#!/usr/bin/python3
import argparse
import logging
from os import listdir
from os.path import isfile, join
from sys import exit

logging.basicConfig(level = logging.INFO)

def parse_args()->tuple[str,str,str, str]:
    parser = argparse.ArgumentParser(description="Generate a C stub for a Skadi network device driver, to be included in Networking subsystem.")
    parser.add_argument('--outfile', type=str, required=True, help='Output path')
    parser.add_argument('--compatible', type=str, required=True, help='Compatible string')
    parser.add_argument('--subsystem-name', type=str, required=True, help='Name of the driver')
    parser.add_argument('--devtype', type=str, required=True, help='Device type: "ethernet", "mdio" or "phy"')

    args = parser.parse_args()



    logging.info(f"Got outfile {args.outfile} subsystem name {args.subsystem_name} compatible {args.compatible} device type {args.devtype}")

    return args.outfile, args.subsystem_name, args.compatible, args.devtype

def generate_stub_ethernet(subsystem_name:str, outfile: str, compatible: str)->None:
    stub = \
f'''#include <sys/types.h>
#include <zephyr/kernel.h>
#include <zephyr/net/ethernet.h>

#include <zephyr/skadi/skadi_ops_driver.h>

#define LOG_MODULE_NAME {subsystem_name}
#define LOG_LEVEL       CONFIG_ETHERNET_LOG_LEVEL
#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(LOG_MODULE_NAME);


#include <zephyr/llext/llext.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_device.h>
#include <zephyr/skadi/skadi_loader.h>

struct {subsystem_name}_device_data {{
    /* capability token for device, not task-id-restricted */
    const struct device *device_token;
}};

'''
    # caller stubs for API functions
    # assume that they are exported by the subsystem
    stub += f'''
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS({subsystem_name}_iface_init, struct net_if *iface);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(enum ethernet_hw_caps, {subsystem_name}_get_capabilities, const struct device *device);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_get_config, const struct device *device, enum ethernet_config_type type, struct ethernet_config *config);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_send, const struct device *dev, struct net_pkt *pkt);
#if defined(CONFIG_PTP) || defined(CONFIG_NET_GPTP)
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(const struct device *, {subsystem_name}_get_ptp_clock, const struct device *dev);
#endif
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_probe, const struct device *dev);
    '''

    stub += f'''
        
        static void (*{subsystem_name}_iface_init_ptr)(struct net_if *iface);
        static enum ethernet_hw_caps (*{subsystem_name}_get_capabilities_ptr)(const struct device *device);
        int (*{subsystem_name}_get_config_ptr)(const struct device *device, enum ethernet_config_type type, struct ethernet_config *config);
        int (*{subsystem_name}_send_ptr)(const struct device *dev, struct net_pkt *pkt);
#if defined(CONFIG_PTP) || defined(CONFIG_NET_GPTP)
        const struct device *(*{subsystem_name}_get_ptp_clock_ptr)(const struct device *dev);
#endif
        int (*{subsystem_name}_probe_ptr)(const struct device *dev);

        static int {subsystem_name}_probe_wrapper(const struct device *device);

        static void {subsystem_name}_iface_init_wrapper(struct net_if *iface){{
            LOG_DBG("Calling iface init!");

            __ASSERT({subsystem_name}_iface_init_ptr != NULL, "Subsystem init pointer should not be 0!");
            __ASSERT(iface->net_if_token, "Subsystem interface wrapper should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_iface_init_ptr, false, false);
            {subsystem_name}_iface_init(iface->net_if_token, {subsystem_name}_iface_init_ptr);
        }}

        static enum ethernet_hw_caps {subsystem_name}_get_capabilities_wrapper(const struct device *device){{
            struct {subsystem_name}_device_data *data = device->data;

            __ASSERT(data->device_token, "Expected device token to be set!");

            LOG_DBG("Calling get_caps!");
            __ASSERT({subsystem_name}_get_capabilities_ptr != NULL, "Subsystem get capabilities pointer should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_get_capabilities_ptr, false, false);
            return {subsystem_name}_get_capabilities(data->device_token, {subsystem_name}_get_capabilities_ptr);
        }}

        static int {subsystem_name}_get_config_wrapper(const struct device *device, enum ethernet_config_type type, struct ethernet_config *config){{
            struct {subsystem_name}_device_data *data = device->data;
            struct ethernet_config *config_token = skadi_cap_ops_derive_arg_wo(config, sizeof(*config));
            int ret;
            
            __ASSERT_NO_MSG(config_token);
            if(!config_token){{
                return -ENOMEM;
            }}

            __ASSERT(data->device_token, "Expected device token to be set!");

            LOG_DBG("Calling get_config!");
            __ASSERT({subsystem_name}_get_config_ptr != NULL, "Subsystem get config pointer should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_get_config_ptr, false, false);
            ret = {subsystem_name}_get_config(data->device_token, type, config_token, {subsystem_name}_get_config_ptr);

            (void)skadi_cap_ops_drop(config_token);

            return ret;
        }}

        static int {subsystem_name}_send_wrapper(const struct device *device, struct net_pkt *pkt){{
            struct {subsystem_name}_device_data *data = device->data;

            __ASSERT(data->device_token, "Expected device token to be set!");

            LOG_DBG("Calling send!");
             __ASSERT({subsystem_name}_send_ptr != NULL, "Subsystem send pointer should not be 0!");
             skadi_subsystem_check_function_pointer({subsystem_name}_send_ptr, false, false);
            return {subsystem_name}_send(data->device_token, pkt, {subsystem_name}_send_ptr);
        }}
#if defined(CONFIG_PTP) || defined(CONFIG_NET_GPTP)
        static const struct device *{subsystem_name}_get_ptp_clock_wrapper(const struct device *device){{
            struct {subsystem_name}_device_data *data = device->data;

            __ASSERT(data->device_token, "Expected device token to be set!");

            LOG_DBG("Calling send!");
             __ASSERT({subsystem_name}_get_ptp_clock_ptr != NULL, "Subsystem send pointer should not be 0!");
             skadi_subsystem_check_function_pointer({subsystem_name}_get_ptp_clock_ptr, false, false);
            return {subsystem_name}_get_ptp_clock(data->device_token, {subsystem_name}_get_ptp_clock_ptr);
        }}
#endif

        static const struct ethernet_api {subsystem_name}_api = {{
	        /* TODO PTP not supported yet */
	        .iface_api.init = {subsystem_name}_iface_init_wrapper,
	        .get_capabilities = {subsystem_name}_get_capabilities_wrapper,
	        .get_config = {subsystem_name}_get_config_wrapper,
	        .send = {subsystem_name}_send_wrapper,
#if defined(CONFIG_PTP) || defined(CONFIG_NET_GPTP)
	        .get_ptp_clock		= {subsystem_name}_get_ptp_clock_wrapper,
#endif
        }};

        /* generate device / net_if wrappers that are readable by the invoked subsystem, i.e., not task-id restricted */
        static void {subsystem_name}_init_iface(struct net_if *iface, void *user_data){{
            void* tmp = NULL;
            const void *old_iface_dev, *old_dev;
            bool ret;
            struct {subsystem_name}_device_data *data;
            skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

            (void) user_data;

            ret = skadi_cap_ops_derive(iface, restriction, sizeof(*iface), skadi_get_capability_offset(iface), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE  | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &tmp);
            __ASSERT(ret != false && tmp != 0, "Expected ops derive to work!");

            iface->net_if_token = (struct net_if *) tmp;
            iface->net_if_or = iface;

            ret = skadi_cap_ops_derive(iface->if_dev, restriction, sizeof(*iface->if_dev), skadi_get_capability_offset(iface->if_dev), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &tmp);
            __ASSERT(ret != false && tmp != 0, "Expected ops derive to work!");
            old_iface_dev = iface->if_dev;
            iface->if_dev = (struct net_if_dev *) tmp;

            old_dev = iface->if_dev->dev;
            data = iface->if_dev->dev->data;
            iface->if_dev->dev = data->device_token;

            LOG_DBG("Initialized iface %p net_dev %p dev %p to iface %p net_dev %p dev %p!", iface, old_iface_dev, old_dev, iface->net_if_token, iface->if_dev, iface->if_dev->dev);

        }} 

        static int {subsystem_name}_probe_wrapper(const struct device *device){{
            struct {subsystem_name}_device_data *data = device->data;
            void *derived_token;
            skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

            __ASSERT(data, "Expected device data pointer to be set!");

            if(skadi_cap_ops_derive(device, restriction, sizeof(*device), skadi_get_capability_offset(device), SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &derived_token) == false || derived_token == 0){{
		        LOG_ERR("Could not derive token for device struct!");
        		return -ENOMEM;
        	}}

            data->device_token = (const struct device *) derived_token;


            {subsystem_name}_iface_init_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_iface_init_callee_trampoline");
            {subsystem_name}_get_capabilities_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_get_capabilities_callee_trampoline");
            {subsystem_name}_get_config_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_get_config_callee_trampoline");
            {subsystem_name}_send_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_send_callee_trampoline");
#if defined(CONFIG_PTP) || defined(CONFIG_NET_GPTP)
            {subsystem_name}_get_ptp_clock_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_get_ptp_clock_callee_trampoline");
#endif
            {subsystem_name}_probe_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_probe_callee_trampoline");

            __ASSERT({subsystem_name}_probe_ptr != NULL, "Subsystem probe pointer should not be 0!");

            LOG_DBG("Initializing device!");

            net_if_foreach({subsystem_name}_init_iface, NULL);

            LOG_DBG("Calling probe function from subsystem %"PRIu32"!", SKADI_CURRENT_TASK_ID);

            skadi_subsystem_check_function_pointer({subsystem_name}_probe_ptr, false, false);

            return {subsystem_name}_probe(data->device_token, {subsystem_name}_probe_ptr);
        }}

        #define ETHERNET_DRIVER_SUBSYSTEM_INIT(inst)                                                \
                                                                                                    \
            static struct {subsystem_name}_device_data data_##inst = {{ 0 }};                       \
            /* config and data are handled by the driver itself */                                  \
            ETH_NET_DEVICE_DT_INST_DEFINE(inst, {subsystem_name}_probe_wrapper, NULL, &data_##inst, \
                            NULL, CONFIG_ETH_INIT_PRIORITY,                                         \
                            &{subsystem_name}_api, NET_ETH_MTU);
        
        #define DT_DRV_COMPAT {compatible}
        DT_INST_FOREACH_STATUS_OKAY(ETHERNET_DRIVER_SUBSYSTEM_INIT);
        
    '''

    with(open(outfile,"w") as file):
        file.write(stub)
    
    logging.info(f"Created output stub {outfile}!")

def generate_stub_mdio(subsystem_name:str, outfile: str, compatible: str)->None:
    stub = \
f'''#include <sys/types.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/mdio.h>

#include <zephyr/skadi/skadi_ops_driver.h>

#define LOG_MODULE_NAME {subsystem_name}
#define LOG_LEVEL       CONFIG_ETHERNET_LOG_LEVEL
#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(LOG_MODULE_NAME);


#include <zephyr/llext/llext.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_device.h>
#include <zephyr/skadi/skadi_loader.h>

struct {subsystem_name}_device_data {{
    /* capability token for device, not task-id-restricted */
    const struct device *device_token;
}};
'''
    # caller stubs for API functions
    # assume that they are exported by the subsystem
    stub += f'''
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS({subsystem_name}_bus_disable, const struct device *dev);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS({subsystem_name}_bus_enable, const struct device *dev);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_read, const struct device *dev, uint8_t prtad, uint8_t devad, uint16_t *data);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_write, const struct device *dev, uint8_t prtad, uint8_t devad, uint16_t data);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_probe, const struct device *dev);
    '''

    stub += f'''
        
        static void (*{subsystem_name}_bus_disable_ptr)(const struct device *dev);
        static void (*{subsystem_name}_bus_enable_ptr)(const struct device *dev);
        static int (*{subsystem_name}_read_ptr)(const struct device *dev, uint8_t prtad, uint8_t devad, uint16_t *data);
        static int (*{subsystem_name}_write_ptr)(const struct device *dev, uint8_t prtad, uint8_t devad, uint16_t data);
        static int (*{subsystem_name}_probe_ptr)(const struct device *dev);
        
        static int {subsystem_name}_probe_wrapper(const struct device *device);

        static void {subsystem_name}_bus_disable_wrapper(const struct device *dev){{
            struct {subsystem_name}_device_data *data = dev->data;

            __ASSERT(data->device_token, "Expected device token to be set!");

            LOG_DBG("Disable bus!");
            __ASSERT({subsystem_name}_bus_disable_ptr != NULL, "Bus disable pointer should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_bus_disable_ptr, false, false);
            {subsystem_name}_bus_disable(data->device_token, {subsystem_name}_bus_disable_ptr);
            LOG_DBG("Disable bus done!");
        }}

        static int {subsystem_name}_probe_wrapper(const struct device *device);

        static void {subsystem_name}_bus_enable_wrapper(const struct device *dev){{
            struct {subsystem_name}_device_data *data = dev->data;

            __ASSERT(data->device_token, "Expected device token to be set!");
            LOG_DBG("Enable bus!");

            __ASSERT({subsystem_name}_bus_enable_ptr != NULL, "Bus enable pointer should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_bus_enable_ptr, false, false);
            {subsystem_name}_bus_enable(data->device_token, {subsystem_name}_bus_enable_ptr);
            LOG_DBG("Enable bus done!");
        }}

        static int {subsystem_name}_read_wrapper(const struct device *dev, uint8_t prtad, uint8_t devad, uint16_t *data){{
            int ret;
            struct {subsystem_name}_device_data *dev_data = dev->data;
            void *data_token;
            skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

            if(skadi_cap_ops_derive(data, restriction, sizeof(*data), skadi_get_capability_offset(data), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &data_token) == false || data_token == 0){{
		        LOG_ERR("Could not derive token for data!");
        		return -ENOMEM;
        	}}

            __ASSERT(dev_data->device_token, "Expected device token to be set!");

            LOG_DBG("Read via MDIO!");

            __ASSERT({subsystem_name}_read_ptr != NULL, "Read pointer should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_read_ptr, false, false);
            ret = {subsystem_name}_read(dev_data->device_token, prtad, devad, (uint16_t*)data_token, {subsystem_name}_read_ptr);
            LOG_DBG("Read done!");

            skadi_cap_ops_drop(data_token);

            return ret;
        }}

        static int {subsystem_name}_write_wrapper(const struct device *dev, uint8_t prtad, uint8_t devad, uint16_t data){{
            int ret;
            struct {subsystem_name}_device_data *dev_data = dev->data;

            __ASSERT(dev_data->device_token, "Expected device token to be set!");

            LOG_DBG("Write via MDIO!");
            
            __ASSERT({subsystem_name}_write_ptr != NULL, "Write pointer should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_write_ptr, false, false);
            ret = {subsystem_name}_write(dev_data->device_token, prtad, devad, data, {subsystem_name}_write_ptr);
            LOG_DBG("Write done");
            return ret;
        }}

        static const struct mdio_driver_api {subsystem_name}_api = {{
	        .bus_disable = {subsystem_name}_bus_disable_wrapper,
	        .bus_enable = {subsystem_name}_bus_enable_wrapper,
	        .read = {subsystem_name}_read_wrapper,
	        .write = {subsystem_name}_write_wrapper
        }};

        static int {subsystem_name}_probe_wrapper(const struct device *device){{
            struct {subsystem_name}_device_data *data = device->data;
            void *derived_token;
            skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

            __ASSERT(data, "Expected device data pointer to be set!");

            if(skadi_cap_ops_derive(device, restriction, sizeof(*device), skadi_get_capability_offset(device), SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &derived_token) == false || derived_token == 0){{
		        LOG_ERR("Could not derive token for device struct!");
        		return -ENOMEM;
        	}}

            data->device_token = (const struct device *) derived_token;

            {subsystem_name}_bus_disable_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_bus_disable_callee_trampoline");
            {subsystem_name}_bus_enable_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_bus_enable_callee_trampoline");
            {subsystem_name}_read_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_read_callee_trampoline");
            {subsystem_name}_write_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_write_callee_trampoline");
            {subsystem_name}_probe_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_probe_callee_trampoline");

            __ASSERT({subsystem_name}_probe_ptr != NULL, "Subsystem probe pointer should not be 0!");

            skadi_subsystem_check_function_pointer({subsystem_name}_probe_ptr, false, false);

            return {subsystem_name}_probe(data->device_token, {subsystem_name}_probe_ptr);
        }}

        #define MDIO_DRIVER_SUBSYSTEM_INIT(inst)                                                        \
                                                                                                        \
            static struct {subsystem_name}_device_data data_##inst = {{ 0 }};                           \
            /* config and data are handled by the driver itself */                                      \
            DEVICE_DT_INST_DEFINE_NOEXPORT(inst, {subsystem_name}_probe_wrapper, NULL, &data_##inst,    \
                            NULL, POST_KERNEL, CONFIG_MDIO_INIT_PRIORITY,                               \
                            &{subsystem_name}_api);
        
        #define DT_DRV_COMPAT {compatible}
        DT_INST_FOREACH_STATUS_OKAY(MDIO_DRIVER_SUBSYSTEM_INIT);
        
    '''

    with(open(outfile,"w") as file):
        file.write(stub)
    
    logging.info(f"Created output stub {outfile}!")

def generate_stub_phy(subsystem_name:str, outfile: str, compatible: str)->None:
    stub = \
f'''#include <sys/types.h>
#include <zephyr/kernel.h>
#include <zephyr/drivers/mdio.h>
#include <zephyr/net/phy.h>
#include <zephyr/net/mii.h>

#include <zephyr/skadi/skadi_ops_driver.h>

#define LOG_MODULE_NAME {subsystem_name}
#define LOG_LEVEL       CONFIG_PHY_LOG_LEVEL
#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(LOG_MODULE_NAME);


#include <zephyr/llext/llext.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_device.h>
#include <zephyr/skadi/skadi_loader.h>

struct {subsystem_name}_device_data {{
    /* capability token for device, not task-id-restricted */
    const struct device *device_token;
}};

'''
    # caller stubs for API functions
    # assume that they are exported by the subsystem
    stub += f'''
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_cfg_link, const struct device *dev, enum phy_link_speed speeds);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_get_link, const struct device *dev, struct phy_link_state *state);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_link_cb_set, const struct device *dev, phy_callback_t callback, void *user_data);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_read, const struct device *dev, uint16_t reg_addr, uint32_t *value);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_write, const struct device *dev, uint16_t reg_addr, uint32_t value);
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, {subsystem_name}_initialize, const struct device *dev);
    '''

    stub += f'''
        
        static int (*{subsystem_name}_cfg_link_ptr)(const struct device *dev, enum phy_link_speed speeds);
        static int (*{subsystem_name}_get_link_ptr)(const struct device *dev, struct phy_link_state *state);
        static int (*{subsystem_name}_link_cb_set_ptr)(const struct device *dev, phy_callback_t callback, void *user_data);
        static int (*{subsystem_name}_read_ptr)(const struct device *dev, uint16_t reg_addr, uint32_t *value);
        static int (*{subsystem_name}_write_ptr)(const struct device *dev, uint16_t reg_addr, uint32_t value);
        static int (*{subsystem_name}_initialize_ptr)(const struct device *dev);
        
        static int {subsystem_name}_initialize_wrapper(const struct device *device);

        static int {subsystem_name}_cfg_link_wrapper(const struct device *dev, enum phy_link_speed speeds){{
             struct {subsystem_name}_device_data *dev_data = dev->data;

            __ASSERT(dev_data->device_token, "Expected device token to be set!");

            __ASSERT({subsystem_name}_cfg_link_ptr != NULL, "Config link pointer should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_cfg_link_ptr, false, false);
            return {subsystem_name}_cfg_link(dev_data->device_token, speeds, {subsystem_name}_cfg_link_ptr);
        }}

        static int {subsystem_name}_get_link_wrapper(const struct device *dev, struct phy_link_state *state){{
            struct {subsystem_name}_device_data *dev_data = dev->data;
            void *state_token;
            int ret;
            skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

            if(skadi_cap_ops_derive(state, restriction, sizeof(*state), skadi_get_capability_offset(state), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &state_token) == false || state_token == 0){{
		        LOG_ERR("Could not derive token for state!");
        		return -ENOMEM;
        	}}

            __ASSERT(dev_data->device_token, "Expected device token to be set!");
            
            __ASSERT({subsystem_name}_get_link_ptr != NULL, "Get link pointer should not be 0!");

            skadi_subsystem_check_function_pointer({subsystem_name}_get_link_ptr, false, false);
            ret = {subsystem_name}_get_link(dev_data->device_token, (struct phy_link_state *) state_token, {subsystem_name}_get_link_ptr);

            skadi_cap_ops_drop(state_token);

            return ret;
        }}

        static int {subsystem_name}_link_cb_set_wrapper(const struct device *dev, phy_callback_t callback, void *user_data){{
             struct {subsystem_name}_device_data *dev_data = dev->data;

            __ASSERT(dev_data->device_token, "Expected device token to be set!");

            __ASSERT({subsystem_name}_link_cb_set_ptr != NULL, "Set callback pointer should not be 0!");

            skadi_subsystem_check_function_pointer({subsystem_name}_link_cb_set_ptr, false, false);
            return {subsystem_name}_link_cb_set(dev_data->device_token, callback, user_data, {subsystem_name}_link_cb_set_ptr);
        }}

        static int {subsystem_name}_read_wrapper(const struct device *dev, uint16_t reg_addr, uint32_t *data){{
            struct {subsystem_name}_device_data *dev_data = dev->data;
            void *data_token;
            int ret;
            skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

            if(skadi_cap_ops_derive(data, restriction, sizeof(*data), skadi_get_capability_offset(data), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &data_token) == false || data_token == 0){{
		        LOG_ERR("Could not derive token for data!");
        		return -ENOMEM;
        	}}

            __ASSERT(dev_data->device_token, "Expected device token to be set!");

            __ASSERT({subsystem_name}_read_ptr != NULL, "Read pointer should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_read_ptr, false, false);
            ret = {subsystem_name}_read(dev_data->device_token, reg_addr, (uint32_t *) data, {subsystem_name}_read_ptr);

            skadi_cap_ops_drop(data_token);

            return ret;
        }}

        static int {subsystem_name}_write_wrapper(const struct device *dev, uint16_t reg_addr, uint32_t value){{
            struct {subsystem_name}_device_data *dev_data = dev->data;

            __ASSERT(dev_data->device_token, "Expected device token to be set!");

            __ASSERT({subsystem_name}_write_ptr != NULL, "Write pointer should not be 0!");
            skadi_subsystem_check_function_pointer({subsystem_name}_write_ptr, false, false);
            return {subsystem_name}_write(dev_data->device_token, reg_addr, value, {subsystem_name}_write_ptr);
        }}

        static const struct ethphy_driver_api {subsystem_name}_api = {{
	        .get_link = {subsystem_name}_get_link_wrapper,
	        .cfg_link = {subsystem_name}_cfg_link_wrapper,
	        .link_cb_set = {subsystem_name}_link_cb_set_wrapper,
	        .read = {subsystem_name}_read_wrapper,
	        .write = {subsystem_name}_write_wrapper,
        }};

        static int {subsystem_name}_initialize_wrapper(const struct device *device){{

            struct {subsystem_name}_device_data *data = device->data;
            void *derived_token;
            skadi_restriction_t restriction = SKADI_NO_RESTRICTION;

            __ASSERT(data, "Expected device data pointer to be set!");

            if(skadi_cap_ops_derive(device, restriction, sizeof(*device), skadi_get_capability_offset(device), SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &derived_token) == false || derived_token == 0){{
		        LOG_ERR("Could not derive token for device struct!");
        		return -ENOMEM;
        	}}

            data->device_token = (const struct device *) derived_token;

            {subsystem_name}_cfg_link_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_cfg_link_callee_trampoline");
            {subsystem_name}_get_link_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_get_link_callee_trampoline");
            {subsystem_name}_link_cb_set_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_link_cb_set_callee_trampoline");
            {subsystem_name}_read_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_read_callee_trampoline");
            {subsystem_name}_write_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_write_callee_trampoline");
            {subsystem_name}_initialize_ptr = (void *) skadi_loader_get_symbol("{subsystem_name}_initialize_callee_trampoline");
            
            __ASSERT({subsystem_name}_initialize_ptr != NULL, "Subsystem initialize pointer should not be 0!");

            skadi_subsystem_check_function_pointer({subsystem_name}_initialize_ptr, false, false);

            return {subsystem_name}_initialize(data->device_token, {subsystem_name}_initialize_ptr);
        }}

        #define PHY_DRIVER_SUBSYSTEM_INIT(inst)                                                                 \
                                                                                                                \
           static struct {subsystem_name}_device_data data_##inst = {{ 0 }};                                    \
            /* config and data are handled by the driver itself */                                              \
            DEVICE_DT_INST_DEFINE_NOEXPORT(inst, {subsystem_name}_initialize_wrapper, NULL, &data_##inst,       \
                            NULL, POST_KERNEL, CONFIG_PHY_INIT_PRIORITY,                                        \
                            &{subsystem_name}_api);
        
        #define DT_DRV_COMPAT {compatible}
        DT_INST_FOREACH_STATUS_OKAY(PHY_DRIVER_SUBSYSTEM_INIT);
        
    '''

    with(open(outfile,"w") as file):
        file.write(stub)
    
    logging.info(f"Created output stub {outfile}!")


def main():
    outfile,subsystem_name,compatible,devtype = parse_args()

    if devtype == "ethernet":
        generate_stub_ethernet(subsystem_name, outfile, compatible)
        return
    if devtype == "mdio":
        generate_stub_mdio(subsystem_name, outfile, compatible)
        return
    if devtype == "phy":
        generate_stub_phy(subsystem_name, outfile, compatible)
        return

    logging.error(f"Unknown device type {devtype}")
    exit(1)
    

if __name__ == "__main__":
    main()
