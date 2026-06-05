#ifndef SKADI_MDIO_H
#define SKADI_MDIO_H
    #include <zephyr/device.h>
    #include <zephyr/drivers/mdio.h>
    #include <zephyr/skadi/skadi_subsystem.h>
    

    /* function pointer wrappers for API functions */
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(skadi_mdio_bus_disable_fn, const struct device *dev);
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(skadi_mdio_bus_enable_fn, const struct device *dev);
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_mdio_read_fn, const struct device *dev, uint8_t prtad, uint8_t devad, uint16_t *data);
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_mdio_write_fn, const struct device *dev, uint8_t prtad, uint8_t devad, uint16_t data);

	static inline void skadi_mdio_bus_disable(const struct device *dev)
	{
		const struct mdio_driver_api *api =
			(const struct mdio_driver_api *)dev->api;

		if (api->bus_disable == NULL) {
			return;
		}

		skadi_subsystem_check_function_pointer(api->bus_disable, true, false);

		return skadi_mdio_bus_disable_fn(dev, api->bus_disable);
	}

	static inline void skadi_mdio_bus_enable(const struct device *dev)
	{
		const struct mdio_driver_api *api =
			(const struct mdio_driver_api *)dev->api;

		if (api->bus_enable == NULL) {
			return;
		}

		skadi_subsystem_check_function_pointer(api->bus_enable, true, false);

		return skadi_mdio_bus_enable_fn(dev, api->bus_enable);
	}

	static inline int skadi_mdio_read(const struct device *dev, uint8_t prtad,
				   uint8_t regad, uint16_t *data)
	{
		const struct mdio_driver_api *api =
			(const struct mdio_driver_api *)dev->api;
		uint16_t *data_token;
		int ret;

		data_token = skadi_cap_ops_derive_arg_wo(data, sizeof(uint16_t));

		__ASSERT_NO_MSG(data_token);
		if(!data_token){
			return -ENOMEM;
		}



		if (api->read == NULL) {
			return -ENOSYS;
		}

		skadi_subsystem_check_function_pointer(api->read, true, false);

		ret = skadi_mdio_read_fn(dev, prtad, regad, data_token, api->read);

		(void)skadi_cap_ops_drop(data_token);

		return ret;
	}

	static inline int skadi_mdio_write(const struct device *dev, uint8_t prtad,
				   uint8_t regad, uint16_t data)
	{
		const struct mdio_driver_api *api =
			(const struct mdio_driver_api *)dev->api;

		if (api->write == NULL) {
			return -ENOSYS;
		}

		skadi_subsystem_check_function_pointer(api->write, true, false);

		return skadi_mdio_write_fn(dev, prtad, regad, data, api->write);
	}

    
#endif
