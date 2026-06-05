#ifndef SKADI_PHY_H
#define SKADI_PHY_H
    #include <zephyr/device.h>
    #include <zephyr/net/phy.h>
    #include <zephyr/skadi/skadi_subsystem.h>
    
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_phy_configure_link_fn, const struct device *dev, enum phy_link_speed speeds);
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_phy_get_link_state_fn, const struct device *dev, struct phy_link_state *state);
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_phy_link_callback_set_fn, const struct device *dev, phy_callback_t callback, void *user_data);
	

    /**
	 * @brief      Configure PHY link
	 *
	 * This route configures the advertised link speeds.
	 *
	 * @param[in]  dev     PHY device structure
	 * @param      speeds  OR'd link speeds to be advertised by the PHY
	 *
	 * @retval 0 If successful.
	 * @retval -EIO If communication with PHY failed.
	 * @retval -ENOTSUP If not supported.
	 */
    static inline int skadi_phy_configure_link(const struct device *dev,
				     enum phy_link_speed speeds){
		const struct ethphy_driver_api *api =
		(const struct ethphy_driver_api *)dev->api;

		skadi_subsystem_check_function_pointer(api->cfg_link, true, false);

		return skadi_phy_configure_link_fn(dev, speeds, api->cfg_link);
	}

	/**
	 * @brief      Get PHY link state
	 *
	 * Returns the current state of the PHY link. This can be used by
	 * to determine when a link is up and the negotiated link speed.
	 *
	 *
	 * @param[in]  dev    PHY device structure
	 * @param      state  Pointer to receive PHY state
	 *
	 * @retval 0 If successful.
	 * @retval -EIO If communication with PHY failed.
	 */
	static inline int skadi_phy_get_link_state(const struct device *dev,
				     struct phy_link_state *state){
		const struct ethphy_driver_api *api =
		(const struct ethphy_driver_api *)dev->api;
		struct phy_link_state *state_token;
		int ret;

		state_token = skadi_cap_ops_derive_arg_wo(state, sizeof(*state));

		__ASSERT_NO_MSG(state_token);
		if(!state_token){
			return -ENOMEM;
		}

		skadi_subsystem_check_function_pointer(api->get_link, true, false);

		ret = skadi_phy_get_link_state_fn(dev, state_token, api->get_link);
		
		(void)skadi_cap_ops_drop(state_token);

		return ret;
	}
    
	/**
	 * @brief      Set link state change callback
	 *
	 * Sets a callback that is invoked when link state changes. This is the
	 * preferred method for ethernet drivers to be notified of the PHY link
	 * state change.
	 *
	 * @param[in]  dev        PHY device structure
	 * @param      callback   Callback handler
	 * @param      user_data  Pointer to data specified by user.
	 *
	 * @retval 0 If successful.
	 * @retval -ENOTSUP If not supported.
	 */
	int skadi_phy_link_callback_set(const struct device *dev,
					phy_callback_t callback,
					void *user_data){
		const struct ethphy_driver_api *api =
		(const struct ethphy_driver_api *)dev->api;

		skadi_subsystem_check_function_pointer(api->link_cb_set, true, false);

		return skadi_phy_link_callback_set_fn(dev, callback, user_data, api->link_cb_set);
	}
#endif
