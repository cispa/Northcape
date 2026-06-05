#include <zephyr/logging/log.h>

#include <zephyr/skadi/skadi_ariane_genesysii.h>
#include <zephyr/skadi/skadi_benchmark.h>
#ifdef CONFIG_SKADI_LOADER
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_loader.h>
#endif

#include <cv64a6.h>

LOG_MODULE_REGISTER(skadi_irq_test, CONFIG_LOG_DEFAULT_LEVEL);

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(bool, irq_client_start_test);
#else
extern bool irq_client_start_test(void);
#endif

#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_MAIN(void)
#else
int main(void)
#endif
{	
	bool is_ok;

#if defined(CONFIG_SKADI_LOADER)
	skadi_evaluate_boot_time();
#endif
	is_ok = irq_client_start_test();

	LOG_INF("irq_client finished test!");
	
	return is_ok == true ? 0 : 1;
}
#ifdef CONFIG_SKADI_LOADER
SKADI_SUBSYSTEM_MAIN_END
#endif
