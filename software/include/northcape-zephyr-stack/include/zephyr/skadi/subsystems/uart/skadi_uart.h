#ifndef SKADI_UART_H
#define SKADI_UART_H

#include <zephyr/drivers/uart.h>
#include <zephyr/skadi/skadi_subsystem.h>

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_irq_callback_user_data_set, const struct device *dev, uart_irq_callback_user_data_t cb, void *user_data);

/**
 * @brief Set the IRQ callback function pointer (legacy).
 *
 * This sets up the callback for IRQ. When an IRQ is triggered,
 * the specified function will be called with the device pointer.
 *
 * @param dev UART device instance.
 * @param cb Pointer to the callback function.
 *
 * @retval 0 On success.
 * @retval -ENOSYS If this function is not implemented.
 * @retval -ENOTSUP If API is not enabled.
 */
static inline int skadi_uart_irq_callback_set(const struct device *dev,
					 uart_irq_callback_user_data_t cb)
{
	return __skadi_uart_irq_callback_user_data_set(dev, cb, NULL);
}

static inline int skadi_uart_irq_callback_user_data_set(const struct device *dev,
					 uart_irq_callback_user_data_t cb, void *user_data)
{
	return __skadi_uart_irq_callback_user_data_set(dev, cb, user_data);
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_callback_set, const struct device *dev, uart_callback_t cb, void *user_data);

static inline int skadi_uart_callback_set(const struct device *dev, uart_callback_t cb, void *user_data)
{
	return __skadi_uart_callback_set(dev, cb, user_data);
}


/**
 * @brief Retrieve line control for UART.
 *
 * @param dev UART device instance.
 * @param ctrl The line control to retrieve (see enum uart_line_ctrl).
 * @param val Pointer to variable where to store the line control value.
 *
 * @retval 0 If successful.
 * @retval -ENOSYS If this function is not implemented.
 * @retval -ENOTSUP If API is not enabled.
 * @retval -errno Other negative errno value in case of failure.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_line_ctrl_get, const struct device *dev, uint32_t ctrl, uint32_t *val);

static inline int skadi_uart_line_ctrl_get(const struct device *dev,
					    uint32_t ctrl, uint32_t *val){
    int ret;
    uint32_t *val_token = skadi_cap_ops_derive_arg_wo(val, sizeof(*val));

    __ASSERT_NO_MSG(val_token);

    if(!val_token){
        return -ENOMEM;
    }

    ret = __skadi_uart_line_ctrl_get(dev, ctrl, val_token);

    skadi_cap_ops_drop(val_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_rx_buf_rsp, const struct device *dev, uint8_t *buf, size_t len);

static inline int skadi_uart_rx_buf_rsp(const struct device *dev, uint8_t *buf,
				  size_t len){
    uint8_t *buf_token = skadi_cap_ops_derive_arg_wo(buf, len);
    int ret;

    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        return -ENOMEM;
    }

    ret = __skadi_uart_rx_buf_rsp(dev, buf_token, len);

    skadi_cap_ops_drop(buf_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_tx, const struct device *dev, const uint8_t *buf, size_t len, int32_t timeout);

static inline int skadi_uart_tx(const struct device *dev, const uint8_t *buf, size_t len, int32_t timeout){
    const uint8_t *buf_token = skadi_cap_ops_derive_arg_ro(buf, len);
    int ret;

    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        return -ENOMEM;
    }

    ret = __skadi_uart_tx(dev, buf_token, len, timeout);

    skadi_cap_ops_drop(buf_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_irq_rx_ready, const struct device *dev);

static inline int skadi_uart_irq_rx_ready(const struct device *dev){
    return __skadi_uart_irq_rx_ready(dev);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_irq_tx_ready, const struct device *dev);

static inline int skadi_uart_irq_tx_ready(const struct device *dev){
    return __skadi_uart_irq_tx_ready(dev);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_fifo_fill, const struct device *dev, const uint8_t *tx_data, int size);

static inline int skadi_uart_fifo_fill(const struct device *dev, const uint8_t *tx_data, int size){
    const uint8_t *buf_token = skadi_cap_ops_derive_arg_ro(tx_data, size);
    int ret;

    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        return -ENOMEM;
    }
    
    ret = __skadi_uart_fifo_fill(dev, buf_token, size);

    skadi_cap_ops_drop(buf_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_fifo_read, const struct device *dev, uint8_t *rx_data, int size);

static inline int skadi_uart_fifo_read(const struct device *dev, uint8_t *rx_data, int size){
    uint8_t *buf_token = skadi_cap_ops_derive_arg_wo(rx_data, size);
    int ret;

    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        return -ENOMEM;
    }
    
    ret = __skadi_uart_fifo_read(dev, buf_token, size);

    skadi_cap_ops_drop(buf_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_uart_irq_rx_disable, const struct device *dev);

static inline void skadi_uart_irq_rx_disable(const struct device *dev){
    __skadi_uart_irq_rx_disable(dev);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_uart_irq_tx_disable, const struct device *dev);

static inline void skadi_uart_irq_tx_disable(const struct device *dev){
    __skadi_uart_irq_tx_disable(dev);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_uart_irq_rx_enable, const struct device *dev);

static inline void skadi_uart_irq_rx_enable(const struct device *dev){
    __skadi_uart_irq_rx_enable(dev);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID( __skadi_uart_irq_tx_enable, const struct device *dev);

static inline void skadi_uart_irq_tx_enable(const struct device *dev){
    __skadi_uart_irq_tx_enable(dev);
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_rx_enable, const struct device *dev, uint8_t *rx_data, size_t size, int32_t timeout);

static inline int skadi_uart_rx_enable(const struct device *dev, uint8_t *rx_data, size_t size, int32_t timeout){
    uint8_t *buf_token = skadi_cap_ops_derive_arg_wo(rx_data, size);
    int ret;

    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        return -ENOMEM;
    }
    
    ret = __skadi_uart_rx_enable(dev, buf_token, size, timeout);

    skadi_cap_ops_drop(buf_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_irq_update, const struct device *dev);

static inline int skadi_uart_irq_update(const struct device *dev){
    return __skadi_uart_irq_update(dev);
}


SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_poll_in, const struct device *dev, unsigned char *p_char);

static inline int skadi_uart_poll_in(const struct device *dev, unsigned char *p_char){
    unsigned char *buf_token = skadi_cap_ops_derive_arg_wo(p_char, sizeof(*p_char));
    int ret;

    __ASSERT_NO_MSG(buf_token);

    if(!buf_token){
        return -ENOMEM;
    }
    
    ret = __skadi_uart_poll_in(dev, buf_token);

    skadi_cap_ops_drop(buf_token);

    return ret;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_uart_poll_out, const struct device *dev, unsigned char out_char);

static inline void skadi_uart_poll_out(const struct device *dev, unsigned char out_char){
    __skadi_uart_poll_out(dev, out_char);
}

/**
 * @brief Check if any IRQs is pending.
 *
 * @param dev UART device instance.
 *
 * @retval 1 If an IRQ is pending.
 * @retval 0 If an IRQ is not pending.
 * @retval -ENOSYS If this function is not implemented.
 * @retval -ENOTSUP If API is not enabled.
 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __skadi_uart_irq_is_pending, const struct device *dev);

static inline int skadi_uart_irq_is_pending(const struct device *dev){
    return __skadi_uart_irq_is_pending(dev);
}

#endif
