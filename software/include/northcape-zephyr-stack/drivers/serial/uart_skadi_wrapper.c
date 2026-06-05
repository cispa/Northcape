#include <zephyr/drivers/uart.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_device.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_uart_wrapper, CONFIG_SKADI_LOG_LEVEL);

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_irq_callback_user_data_set, const struct device *dev_in, uart_irq_callback_user_data_t cb, void *user_data)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);
    const char *reason = "";

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    if(!skadi_subsystem_can_accept_function_pointer((uintptr_t) cb, &reason, SKADI_CURRENT_TASK_ID, true, false)){
        LOG_ERR("Cannot accept callback %p: %s!", cb, reason);
        return -EINVAL;
    }

    return uart_irq_callback_user_data_set(dev, cb, user_data);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_irq_callback_user_data_set)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_callback_set, const struct device *dev_in, uart_callback_t cb, void *user_data)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);
    const char *reason = "";

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    if(!skadi_subsystem_can_accept_function_pointer((uintptr_t) cb, &reason, SKADI_CURRENT_TASK_ID, true, false)){
        LOG_ERR("Cannot accept callback %p: %s!", cb, reason);
        return -EINVAL;
    }

    return uart_callback_set(dev, cb, user_data);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_callback_set)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_line_ctrl_get, const struct device *dev_in, uint32_t ctrl, uint32_t *val)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_line_ctrl_get(dev, ctrl, val);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_line_ctrl_get)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_rx_buf_rsp, const struct device *dev_in, uint8_t *buf, size_t len)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_rx_buf_rsp(dev, buf, len);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_rx_buf_rsp)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_tx, const struct device *dev_in, const uint8_t *buf, size_t len, int32_t timeout)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_tx(dev, buf, len, timeout);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_tx)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_irq_rx_ready, const struct device *dev_in)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_irq_rx_ready(dev);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_irq_rx_ready)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_irq_tx_ready, const struct device *dev_in)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_irq_tx_ready(dev);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_irq_tx_ready)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_fifo_fill, const struct device *dev_in, const uint8_t *tx_data, int size)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_fifo_fill(dev, tx_data, size);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_fifo_fill)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_fifo_read, const struct device *dev_in, uint8_t *rx_data, int size)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_fifo_read(dev, rx_data, size);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_fifo_read)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_uart_irq_rx_disable, const struct device *dev_in)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return;
    }

    return uart_irq_rx_disable(dev);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_irq_rx_disable)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_uart_irq_tx_disable, const struct device *dev_in)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return;
    }

    return uart_irq_tx_disable(dev);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_irq_tx_disable)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_uart_irq_rx_enable, const struct device *dev_in)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return;
    }

    return uart_irq_rx_enable(dev);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_irq_rx_enable)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_uart_irq_tx_enable, const struct device *dev_in)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return;
    }

    return uart_irq_tx_enable(dev);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_irq_tx_enable)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_irq_update, const struct device *dev_in)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_irq_update(dev);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_irq_update)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_rx_enable, const struct device *dev_in, uint8_t *rx_data, size_t size, int32_t timeout)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_rx_enable(dev, rx_data, size, timeout);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_rx_enable)


SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_poll_in, const struct device *dev_in, unsigned char *p_char)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return -EINVAL;
    }

    return uart_poll_in(dev, p_char);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_poll_in)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, __skadi_uart_poll_out, const struct device *dev_in, unsigned char p_char)
{
    const struct device *dev = skadi_find_device_in_section(dev_in);

    __ASSERT_NO_MSG(dev);

    if(!dev){
        LOG_ERR("Could not resolve device %p!", dev);
        return;
    }

    uart_poll_out(dev, p_char);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_poll_out)

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_uart_irq_is_pending, const struct device *dev_in)
{
    return uart_irq_is_pending(dev_in);
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_uart_irq_is_pending)



#if defined(CONFIG_SKADI_LOADER) && !defined(SKADI_SUBSYSTEM)

/* not compiled into subsystem - need to manually init the trampolines */
__boot_func static int uart_wrapper_init_trampolines(void){
    bool init_ok = true;

	init_ok &= __skadi_uart_irq_callback_user_data_set_register_init_function();
    init_ok &= __skadi_uart_callback_set_register_init_function();
    init_ok &= __skadi_uart_line_ctrl_get_register_init_function();
    init_ok &= __skadi_uart_rx_buf_rsp_register_init_function();
    init_ok &= __skadi_uart_tx_register_init_function();
    init_ok &= __skadi_uart_irq_rx_ready_register_init_function();
    init_ok &= __skadi_uart_irq_tx_ready_register_init_function();
    init_ok &= __skadi_uart_fifo_fill_register_init_function();
    init_ok &= __skadi_uart_fifo_read_register_init_function();
    init_ok &= __skadi_uart_irq_rx_disable_register_init_function();
    init_ok &= __skadi_uart_irq_tx_disable_register_init_function();
    init_ok &= __skadi_uart_irq_rx_enable_register_init_function();
    init_ok &= __skadi_uart_irq_tx_enable_register_init_function();
    init_ok &= __skadi_uart_rx_enable_register_init_function();
    init_ok &= __skadi_uart_irq_update_register_init_function();
    init_ok &= __skadi_uart_poll_in_register_init_function();
    init_ok &= __skadi_uart_poll_out_register_init_function();
    init_ok &= __skadi_uart_irq_is_pending_register_init_function();

    return init_ok == true ? 0 : -ENOMEM;
}

SYS_INIT(uart_wrapper_init_trampolines, PRE_KERNEL_1, CONFIG_LOADER_SKADI_TRAMPOLINE_INIT_PRIO);

#endif /* SKADI_SUBSYSTEM */

