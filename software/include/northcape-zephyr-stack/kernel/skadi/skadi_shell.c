#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_shell, CONFIG_SKADI_LOG_LEVEL);

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>

#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>

#include <zephyr/net/net_ip.h>
#include <zephyr/net/net_core.h>
#include <zephyr/net/socket.h>
#include <zephyr/net/zperf.h>

#include "zperf_internal.h"
#include "zperf_session.h"

static long perf_ctr_l1_instr_miss;
static long perf_ctr_l1_data_miss;
static long perf_ctr_l2_resolver_miss;
static long perf_ctr_l2_ops_miss;
static long perf_extra_icache_cycles;
static long perf_missunit_stall_cycles;
static long perf_l2_full_wipe_cycles;

#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
static long perf_subsystem_calls;
#endif

#ifdef CONFIG_SKADI_COUNT_YIELD_CALLS
static long perf_yield_calls;
extern atomic_t skadi_num_yield_calls;
#endif

#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALL_ALLOC_ITERATIONS
extern long skadi_subsystem_callee_trampoline_alloc_its;
static long perf_subsystem_callee_trampoline_alloc_its;

extern long skadi_subsystem_caller_trampoline_alloc_its;
static long perf_subsystem_caller_trampoline_alloc_its;
#endif

static void reset_performance_counters(void){
	perf_ctr_l1_instr_miss = SKADI_PERF_COUNTER_READ_L1_INSTR_MISS();
	perf_ctr_l1_data_miss = SKADI_PERF_COUNTER_READ_L1_DATA_MISS();
	perf_ctr_l2_resolver_miss = SKADI_PERF_COUNTER_READ_L2_RESOLVER_MISS();
	perf_ctr_l2_ops_miss = SKADI_PERF_COUNTER_READ_L2_OPS_MISS();
	perf_extra_icache_cycles = SKADI_PERF_COUNTER_READ_EXTRA_ICACHE_DELAY();
	perf_missunit_stall_cycles = SKADI_PERF_COUNTER_READ_MISSUNIT_STALL();
	perf_l2_full_wipe_cycles = SKADI_PERF_COUNTER_READ_L2_FULL_WIPE();

#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
	perf_subsystem_calls = atomic_get(&skadi_num_subsystem_calls);
#endif

#ifdef CONFIG_SKADI_COUNT_YIELD_CALLS
	perf_yield_calls = atomic_get(&skadi_num_yield_calls);
#endif

#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALL_ALLOC_ITERATIONS
	perf_subsystem_callee_trampoline_alloc_its = skadi_subsystem_callee_trampoline_alloc_its;
	perf_subsystem_caller_trampoline_alloc_its = skadi_subsystem_caller_trampoline_alloc_its;
#endif
}

static void read_performance_counters(const struct shell *sh){
	long diff_l1_instr, diff_l1_data, diff_l2_resolver, diff_l2_ops, diff_extra_cycles, diff_missunit_stall_cycles, diff_l2_full_wipe_cycles;
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
	long diff_subsystem_calls;
#endif
#ifdef CONFIG_SKADI_COUNT_YIELD_CALLS
	long diff_yield_calls;
#endif

#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALL_ALLOC_ITERATIONS
	long diff_callee_alloc_its, diff_caller_alloc_its;
#endif

	diff_l1_instr = SKADI_PERF_COUNTER_READ_L1_INSTR_MISS() - perf_ctr_l1_instr_miss;
	diff_l1_data = SKADI_PERF_COUNTER_READ_L1_DATA_MISS() - perf_ctr_l1_data_miss;
	diff_l2_resolver = SKADI_PERF_COUNTER_READ_L2_RESOLVER_MISS() - perf_ctr_l2_resolver_miss;
	diff_l2_ops = SKADI_PERF_COUNTER_READ_L2_OPS_MISS() - perf_ctr_l2_ops_miss;
	diff_extra_cycles = SKADI_PERF_COUNTER_READ_EXTRA_ICACHE_DELAY() - perf_extra_icache_cycles;
	diff_missunit_stall_cycles = SKADI_PERF_COUNTER_READ_MISSUNIT_STALL() - perf_missunit_stall_cycles;
	diff_l2_full_wipe_cycles = SKADI_PERF_COUNTER_READ_L2_FULL_WIPE() - perf_l2_full_wipe_cycles;
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
	diff_subsystem_calls = atomic_get(&skadi_num_subsystem_calls) - perf_subsystem_calls;
#endif
#ifdef CONFIG_SKADI_COUNT_YIELD_CALLS
	diff_yield_calls = atomic_get(&skadi_num_yield_calls) - perf_yield_calls;
#endif
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALL_ALLOC_ITERATIONS
	diff_callee_alloc_its = skadi_subsystem_callee_trampoline_alloc_its - perf_subsystem_callee_trampoline_alloc_its;
	diff_caller_alloc_its = skadi_subsystem_caller_trampoline_alloc_its - perf_subsystem_caller_trampoline_alloc_its;
#endif
	shell_fprintf(sh, SHELL_INFO, "L1 instruction misses      %ld\n", diff_l1_instr);
	shell_fprintf(sh, SHELL_INFO, "L1 data misses             %ld\n", diff_l1_data);
	shell_fprintf(sh, SHELL_INFO, "L2 resolver misses         %ld\n", diff_l2_resolver);
	shell_fprintf(sh, SHELL_INFO, "L2 ops misses              %ld\n", diff_l2_ops);
	shell_fprintf(sh, SHELL_INFO, "extra icache cycles        %ld\n", diff_extra_cycles);
	shell_fprintf(sh, SHELL_INFO, "missunit stall cycles      %ld\n", diff_missunit_stall_cycles);
	shell_fprintf(sh, SHELL_INFO, "L2 full wipes after spec   %ld\n", diff_l2_full_wipe_cycles);
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALLS
	shell_fprintf(sh, SHELL_INFO, "number subsystem calls     %ld\n", diff_subsystem_calls);
#endif
#ifdef CONFIG_SKADI_COUNT_YIELD_CALLS
	shell_fprintf(sh, SHELL_INFO, "number yield calls         %ld\n", diff_yield_calls);
#endif
#ifdef CONFIG_SKADI_COUNT_SUBSYSTEM_CALL_ALLOC_ITERATIONS
	shell_fprintf(sh, SHELL_INFO, "caller subs. call allocs   %ld\n", diff_callee_alloc_its);
	shell_fprintf(sh, SHELL_INFO, "callee subs. call allocs   %ld\n", diff_callee_alloc_its);
#endif
}

static int cmd_cache_read(const struct shell *sh, size_t argc, char *argv[]){
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);


	read_performance_counters(sh);
	reset_performance_counters();

	return 0;
}

static int cmd_unsupported(const struct shell *sh, size_t argc, char *argv[]){
	ARG_UNUSED(argc);
	
	shell_fprintf(sh, SHELL_INFO, "Unsupported command %s\n", argv[0]);
	return -ENOTSUP;
}

SHELL_STATIC_SUBCMD_SET_CREATE(skadi_cache_read,
	SHELL_CMD(read, NULL,
		  "\n",
		  cmd_cache_read),
	SHELL_SUBCMD_SET_END
);

#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS

static int cmd_ops_cycle_read(const struct shell *sh, size_t argc, char *argv[]){
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);


	shell_fprintf(sh, SHELL_INFO, "Create   cycles:                 %ld\n", atomic_get(&skadi_cycles_create));
	shell_fprintf(sh, SHELL_INFO, "Create   cycles (ops):           %ld\n", atomic_get(&skadi_cycles_create_ops));
	shell_fprintf(sh, SHELL_INFO, "Create   failed occ. checks:     %ld\n", atomic_get(&skadi_failed_occupied_checks_create_ops));
	shell_fprintf(sh, SHELL_INFO, "Derive   cycles:                 %ld\n", atomic_get(&skadi_cycles_derive));
	shell_fprintf(sh, SHELL_INFO, "Derive   cycles (ops):           %ld\n", atomic_get(&skadi_cycles_derive_ops));
	shell_fprintf(sh, SHELL_INFO, "Derive   failed occ. checks:     %ld\n", atomic_get(&skadi_failed_occupied_checks_derive_ops));
	shell_fprintf(sh, SHELL_INFO, "Drop     cycles:                 %ld\n", atomic_get(&skadi_cycles_drop));
	shell_fprintf(sh, SHELL_INFO, "Drop     cycles (ops):           %ld\n", atomic_get(&skadi_cycles_drop_ops));
	shell_fprintf(sh, SHELL_INFO, "Merge    cycles:                 %ld\n", atomic_get(&skadi_cycles_merge));
	shell_fprintf(sh, SHELL_INFO, "Merge    cycles (ops):           %ld\n", atomic_get(&skadi_cycles_merge_ops));
	shell_fprintf(sh, SHELL_INFO, "Merge    failed occ. checks:     %ld\n", atomic_get(&skadi_failed_occupied_checks_merge_ops));
	shell_fprintf(sh, SHELL_INFO, "Clone    cycles:                 %ld\n", atomic_get(&skadi_cycles_clone));
	shell_fprintf(sh, SHELL_INFO, "Clone    cycles (ops):           %ld\n", atomic_get(&skadi_cycles_clone_ops));
	shell_fprintf(sh, SHELL_INFO, "Clone    failed occ. checks:     %ld\n", atomic_get(&skadi_failed_occupied_checks_clone_ops));
	shell_fprintf(sh, SHELL_INFO, "Revoke   cycles:                 %ld\n", atomic_get(&skadi_cycles_revoke));
	shell_fprintf(sh, SHELL_INFO, "Revoke   cycles (ops):           %ld\n", atomic_get(&skadi_cycles_revoke_ops));
	shell_fprintf(sh, SHELL_INFO, "Revoke   failed occ. checks:     %ld\n", atomic_get(&skadi_failed_occupied_checks_revoke_ops));
	shell_fprintf(sh, SHELL_INFO, "Lock     cycles:                 %ld\n", atomic_get(&skadi_cycles_lock));
	shell_fprintf(sh, SHELL_INFO, "Lock     cycles (ops):           %ld\n", atomic_get(&skadi_cycles_lock_ops));
	shell_fprintf(sh, SHELL_INFO, "Lock     failed occ. checks:     %ld\n", atomic_get(&skadi_failed_occupied_checks_lock_ops));
	shell_fprintf(sh, SHELL_INFO, "Inspect  cycles:                 %ld\n", atomic_get(&skadi_cycles_inspect));
	shell_fprintf(sh, SHELL_INFO, "Inspect  cycles (ops):           %ld\n", atomic_get(&skadi_cycles_inspect_ops));
	shell_fprintf(sh, SHELL_INFO, "Restrict cycles:                 %ld\n", atomic_get(&skadi_cycles_restrict));
	shell_fprintf(sh, SHELL_INFO, "Restrict cycles (ops)            %ld\n", atomic_get(&skadi_cycles_restrict_ops));
	shell_fprintf(sh, SHELL_INFO, "Sweep    cycles:                 %ld\n", atomic_get(&skadi_cycles_sweep));
	shell_fprintf(sh, SHELL_INFO, "Sweep    cycles (ops)            %ld\n", atomic_get(&skadi_cycles_sweep_ops));
	return 0;
}

SHELL_STATIC_SUBCMD_SET_CREATE(skadi_ops_cycle_read,
	SHELL_CMD(ops_cycle_read, NULL,
		  "\n",
		  cmd_ops_cycle_read),
	SHELL_SUBCMD_SET_END
);

#endif

SHELL_STATIC_SUBCMD_SET_CREATE(skadi_commands,
	SHELL_CMD(cache, &skadi_cache_read,
		  "Access Skadi cache statistics",
		  cmd_unsupported),
#ifdef CONFIG_SKADI_TRACK_CYCLES_OPS
	SHELL_CMD(ops, &skadi_ops_cycle_read,
		  "Access skadi operations module statistics",
		  cmd_unsupported),
#endif
	SHELL_SUBCMD_SET_END
);

SHELL_CMD_REGISTER(skadi, &skadi_commands, "Skadi commands", NULL);
