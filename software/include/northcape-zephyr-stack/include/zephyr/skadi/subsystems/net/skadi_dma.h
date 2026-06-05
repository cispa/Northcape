#ifndef SKADI_DMA_H
#define SKADI_DMA_H
    #include <zephyr/device.h>
    #include <zephyr/drivers/dma.h>
    #include <zephyr/skadi/skadi_subsystem.h>
    
    /* non-standard function of xilinx AXI DMA; returns last packet's length */
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(unsigned int, dma_xilinx_axi_dma_last_received_frame_length, const struct device *dev);

	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(void, dma_xilinx_axi_dma_channel_uninhibit, const struct device *dev_in, uint32_t channel_num, int key);
	SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, dma_xilinx_axi_dma_channel_inhibit, const struct device *dev_in, uint32_t channel_num);

    /* function pointer wrappers for API functions */
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_dma_start_stop_fn, const struct device *dev, uint32_t channel);
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_dma_config_fn, const struct device *dev, uint32_t channel, struct dma_config *config);
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_dma_reload_fn, const struct device *dev, uint32_t channel, uint64_t src, uint64_t dst, size_t size);

    static inline int skadi_dma_start(const struct device *dev, uint32_t channel)
    {
	const struct dma_driver_api *api =
		(const struct dma_driver_api *)dev->api;

	skadi_subsystem_check_function_pointer(api->start, true, false);

	return skadi_dma_start_stop_fn(dev, channel, api->start);
    }

    static inline int skadi_dma_stop(const struct device *dev, uint32_t channel)
{
	const struct dma_driver_api *api =
		(const struct dma_driver_api *)dev->api;

	skadi_subsystem_check_function_pointer(api->stop, true, false);

	return skadi_dma_start_stop_fn(dev, channel, api->stop);
}

static inline int skadi_dma_config(const struct device *dev, uint32_t channel,
			     struct dma_config *config)
{
	const struct dma_driver_api *api =
		(const struct dma_driver_api *)dev->api;

	skadi_subsystem_check_function_pointer(api->config, true, false);

	return skadi_dma_config_fn(dev, channel, config, api->config);
}

static inline int skadi_dma_reload(const struct device *dev, uint32_t channel,
			     uint64_t src, uint64_t dst, size_t size)
{
    const struct dma_driver_api *api =
		(const struct dma_driver_api *)dev->api;

	if (api->reload) {
		skadi_subsystem_check_function_pointer(api->reload, true, false);
		return skadi_dma_reload_fn(dev, channel, src, dst, size, api->reload);
	}

	return -ENOSYS;
}
#endif
