/*
 * 
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include <stdio.h>


#include <zephyr/skadi/skadi_subsystem.h>
#include "subsystem.h"

const struct dummy_subsystem_parameter capability_param = {
	.foo = 0x42,
	.bar = 0x21
};

#define SCALAR_PARAM 0x1

SKADI_SUBSYSTEM_MAIN(void)
{	
	int ret;

	printf("Hello World from Skadi main subsystem (task ID %d)!\n",SKADI_CURRENT_TASK_ID);
	printf("Calling subsystem with scalar parameter %d capability parameter {foo: %d, bar: %d}!\n", SCALAR_PARAM, capability_param.foo, capability_param.bar);

	/* 
	 * wrapper makes this look like a normal function call
	 */
	ret = subsystem_call(SCALAR_PARAM, &capability_param);

	printf("Subsystem call status: %d!\n", ret);

	return ret;
}
SKADI_SUBSYSTEM_MAIN_END

/*
 * Called in same order as it would be for zephyr, starting after last subsystem was loaded.
 */
static int dummy_init_fn(void){
	printf("UART console has been initialized, so you should see this text. HI!\n");
	
	return 0;
}
SYS_INIT(dummy_init_fn, POST_KERNEL, 0);
