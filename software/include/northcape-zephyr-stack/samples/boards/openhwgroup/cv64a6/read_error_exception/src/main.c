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
#include <zephyr/skadi/skadi_allocator.h>
#include <zephyr/skadi/skadi_ops_driver.h>

#include <zephyr/random/random.h>

#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(skadi_capability_test, CONFIG_LOG_DEFAULT_LEVEL);

int main(void)
{
	const volatile char *invalid_token = (const volatile char *) 0xffffffffffffffff;
	char read;

	/* invalid read - should trigger exception */
	read = *invalid_token;
	
	
	LOG_INF("Test FAIL - expected exception but read %c\n",read);

	z_cv64a6_finish_test(1);

	return 0;
}
