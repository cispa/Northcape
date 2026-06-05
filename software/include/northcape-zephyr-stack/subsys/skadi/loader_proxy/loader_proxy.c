#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/init.h>

#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_loader_proxy, CONFIG_SKADI_LOG_LEVEL);

static bool loader_available = true;

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uintptr_t, __skadi_loader_proxy_get_symbol, const char *symbol_name);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(__skadi_loader_proxy_z_sys_init_run_level, enum init_level level);

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(uintptr_t, __skadi_loader_get_symbol, const char *symbol_name)
    __ASSERT(loader_available, "Loader has beek nuuked!");

    if(!loader_available){
        return 0;
    }

    return __skadi_loader_proxy_get_symbol(symbol_name);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_loader_get_symbol)


SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(void, z_sys_init_run_level, enum init_level level)
    __ASSERT(loader_available, "Loader has beek nuuked!");

    if(!loader_available){
        return;
    }

	__skadi_loader_proxy_z_sys_init_run_level(level);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(z_sys_init_run_level)

#ifdef CONFIG_SKADI_EARLYCON
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, ____skadi_vprintf_early, const char *format, va_list ap);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, __skadi_vprintf_early, const char *format, va_list ap)
    __ASSERT(loader_available, "Loader has beek nuuked!");

    if(!loader_available){
        return -EINVAL;
    }

    return ____skadi_vprintf_early(format, ap);

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_vprintf_early)
#endif


static int skadi_loader_make_inaccessible(void){
    LOG_INF("Init complete - loader is inaccessible!");
    loader_available=false;

    return 0;
}

SYS_INIT(skadi_loader_make_inaccessible, APPLICATION, CONFIG_SKADI_LOADER_DISABLE_INIT_PRIORITY);
