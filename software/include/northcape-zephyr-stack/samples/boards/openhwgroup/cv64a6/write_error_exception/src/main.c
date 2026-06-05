/*
 * 
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <cv64a6.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>

#include <zephyr/sys/barrier.h>

#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(skadi_capability_test, CONFIG_LOG_DEFAULT_LEVEL);

int main(void)
{
	volatile char *invalid_token = (volatile char *) 0xffffffffffffffff;
	char to_be_written = 'e';

	/* invalid write - should trigger exception */
	*invalid_token = to_be_written;

	/* write commits asynchronously - exception will probably occur during the fence */
	barrier_dmem_fence_full();
	
	LOG_INF("Test FAIL - expected exception on store!");

	z_cv64a6_finish_test(1);

	return 0;
}
