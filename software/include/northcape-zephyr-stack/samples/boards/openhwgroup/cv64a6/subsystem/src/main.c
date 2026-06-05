/*
 * 
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <cv64a6.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>


#include <zephyr/skadi/skadi_ariane_genesysii.h>
#include <zephyr/skadi/skadi_subsystem.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_sched.h>

#include <zephyr/logging/log.h>
#include <zephyr/kernel.h>


LOG_MODULE_REGISTER(skadi_subsystem_test, CONFIG_LOG_DEFAULT_LEVEL);

volatile bool test_ok = false;

SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(void, skadi_subsystem_test_test_ok, bool val)
	test_ok = val;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(skadi_subsystem_test_test_ok)

SKADI_SUBSYSTEM_MAIN(void)
{	
	// test_ok is set asynchronously by the tester client
	while(!test_ok){
		skadi_sleep(K_MSEC(100));
	}

	LOG_INF("Test success :-)");
	z_cv64a6_finish_test(0);
}
SKADI_SUBSYSTEM_MAIN_END
