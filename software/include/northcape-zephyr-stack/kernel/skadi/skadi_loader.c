#include <stdlib.h>

#include <zephyr/skadi/skadi_init_alloc.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_ops_driver.h>
#include <zephyr/skadi/skadi_subsystem.h>

#include <zephyr/skadi/skadi_ariane_genesysii.h>

#include <zephyr/sys/barrier.h>

#include "lz4frame.h"


#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_loader, CONFIG_SKADI_LOG_LEVEL);


#include <zephyr/skadi/skadi_sched.h>

#include <zephyr/init.h>
#include <zephyr/llext/llext.h>
#include <zephyr/llext/buf_loader.h>

#include <zephyr/arch/cache.h>


/* 0 is reserved for us, grants the special privilege to create arbitrary set-task-ID restrictions */
static skadi_task_id_t skadi_loader_next_task_id = 1, skadi_loader_current_subsystem_id = 1;

static inline skadi_task_id_t skadi_loader_get_task_id_for_subsystem(const char *subsystem_name){
#ifdef CONFIG_SKADI_SCHEDULER_RUNS_WITH_LOADER_TASK_ID
    if(strcmp(subsystem_name,"scheduler") == 0){
        return SKADI_TASK_ID_LOADER;
    }
#endif
    /* nuuk needs access to the root capability */
    if(strcmp(subsystem_name,"nuuk") == 0){
        return SKADI_TASK_ID_LOADER;
    }
    return skadi_loader_next_task_id;
}

static uintptr_t relocate_function_symbol(void *symbol_addr, uint32_t function_length, const char *subsystem_name){
    void *relocated_function;
    bool derive_ok;
    skadi_restriction_t restriction = SKADI_TASK_ID_RESTRICTION(skadi_loader_get_task_id_for_subsystem(subsystem_name), SKADI_DEVICE_ID_CPU, SKADI_RESTRICTIONS_SET_TASK_ID);

    derive_ok = skadi_cap_ops_derive_min_cap_type(symbol_addr, restriction, function_length,                                    
                                            (uint32_t)(uintptr_t) skadi_get_capability_offset(symbol_addr), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE  | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,
                                            IS_ENABLED(CONFIG_SKADI_TEXT_ALIGN_12_BIT) ? SKADI_CAPABILITY_TYPE_OFFSET_16_BIT :                              \
                                                        SKADI_CAPABILITY_TYPE_OFFSET_8_BIT,                                                   
                                            &relocated_function);                                                              
    if(!derive_ok || relocated_function == NULL){                                                                                                         
        LOG_ERR("Could not create set-task-id capability!");                                                                     
        k_panic();                                                                                                          
    }

    return (uintptr_t)relocated_function;
}

SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_INIT_FN(bool, skadi_loader_init_functions);

/* for the subsystem-provided initialization functions, if any */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS_ALLOW_SELF(int, skadi_subsystem_init_functions, enum init_level level);
/* nuuk, scheduler (depending on config) run with task ID 0 */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_IMPL_ALLOW_SELF(int, skadi_subsystem_init_functions, 1, enum init_level level);

#ifdef CONFIG_SKADI_SUBSYSTEM_PROVIDES_MAIN
/* for main function */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS(int, skadi_subsystem_main, int argc, char **argv);
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_IMPL(int, skadi_subsystem_main, 2, int argc, char **argv);
#endif

typedef int (*skadi_loader_init_fn_t)(void);

extern void skadi_loader_init_fn_callee_trampoline();
extern void skadi_loader_init_fn_callee_trampoline_end();

typedef bool (*elf_void_fn_t)(int);

static bool skadi_loader_call_init_fini_functions(bool is_init, const elf_void_fn_t *fn_table, int fn_count, const char *subsystem_name)
{
    struct skadi_subsystem_stack *allocator_out;
    void* lock_holder_out;
    uintptr_t trampoline;
    bool retval = true;
    

    trampoline = relocate_function_symbol(skadi_loader_init_fn_callee_trampoline, (uint32_t)((uintptr_t)skadi_loader_init_fn_callee_trampoline_end - (uintptr_t) skadi_loader_init_fn_callee_trampoline), subsystem_name);

    // stack is handed over to the subsystem
    // as it is locked with current_task_id restriction, we cannot drop it
    // so it becomes the task of the subsystem to drop and free it
    uint8_t *top_of_stack = skadi_init_alloc_allocate_subsystem_stack(&allocator_out, &lock_holder_out, skadi_loader_get_task_id_for_subsystem(subsystem_name));

    // icache needs to be flushed to ensure fresh data
    barrier_isync_fence_full();

	for (int i = 0; i < fn_count; i++) {
        // init functions are not necessarily IRQ-safe
        unsigned long irq_key = irq_lock();

		LOG_DBG("calling %s function %p() (via trampoline %p)",
			is_init ? "bringup" : "teardown", (void *)fn_table[i], (void *) trampoline);
        /* we are actually calling the trampoline, which will then jump into the actual init function */
        /* we need to do this to avoid the can-only-jump-into-beginning-of-segment limitation */
		retval &= skadi_loader_init_functions(trampoline, top_of_stack, (uintptr_t) fn_table[i]);

        irq_unlock(irq_key);

        if(!retval){
            LOG_ERR("%s function %p() failed!", is_init ? "bringup" : "teardown", (void *)fn_table[i]);
            break;
        }
	}

    if(skadi_cap_ops_drop((void*)trampoline)!=true){
        LOG_WRN("Could not drop the trampoline!");
    }
    
    /* no longer used */
    skadi_init_alloc_free(top_of_stack);

    return retval;
}

static bool skadi_loader_init_subsystem(struct llext *ext){
    ssize_t ret;
    const bool is_init = true;

    // finding the table requires access to the segment
    ret = llext_get_fn_table(ext, is_init, NULL, 0);
	if (ret < 0) {
		LOG_ERR("Failed to get table size: %d", (int)ret);
		k_panic();
	}

	int fn_count = ret / sizeof(elf_void_fn_t);
	elf_void_fn_t fn_table[fn_count];

	ret = llext_get_fn_table(ext, is_init, &fn_table, sizeof(fn_table));
	if (ret < 0) {
		LOG_ERR("Failed to get function table: %d", (int)ret);
		k_panic();
	}
    return skadi_loader_call_init_fini_functions(true, fn_table, fn_count, ext->name);
}

static const char *current_extension_name;

static bool skadi_loader_current_subsystem_is_libc;

uintptr_t skadi_loader_resolve_well_known_symbol(const struct llext *ext, const char *symbol_name){
    
    ARG_UNUSED(ext);

    __ASSERT_NO_MSG(current_extension_name);

    if(strstr(symbol_name, "__skadi__") == symbol_name){
        const char *expected_end = "_caller_trampolines";
        const char *string_end = strstr(symbol_name, expected_end);
        if(string_end && string_end[strlen(expected_end)] == '\0'){
            /* special caller trampoline */
            struct skadi_subsystem_caller_trampoline **ret;
            ret = skadi_init_alloc_allocate(CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS * sizeof(ret[0]), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_CACHEABLE_ACCESS | SKADI_PERMISSION_CACHEABLE_TLB, false);
            __ASSERT_NO_MSG(ret);
            if(!ret){
                return 0;
            }
            for(int i = 0; i < CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS; i++){
                ret[i] = skadi_init_alloc_allocate_aligned(sizeof(*ret[i]), SKADI_ALL_PERMISSIONS, false, SKADI_CALLER_TRAMPOLINE_ALIGNMENT);

                if(!ret[i]){
                    return 0;
                }
            }
            return (uintptr_t) ret;
        }
    }
#ifdef CONFIG_SKADI_SUBSYS_SYNC_UP
    if(strstr(symbol_name, "__skadi__") == symbol_name){
        const char *expected_end = "_caller_trampolines_irq";
        const char *string_end = strstr(symbol_name, expected_end);
        if(string_end && string_end[strlen(expected_end)] == '\0'){
            /* special caller trampoline */
            struct skadi_subsystem_caller_trampoline **ret;
            ret = skadi_init_alloc_allocate(CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ * sizeof(ret[0]), SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_CACHEABLE_ACCESS | SKADI_PERMISSION_CACHEABLE_TLB, false);
            __ASSERT_NO_MSG(ret);
            if(!ret){
                return 0;
            }
            for(int i = 0; i < CONFIG_SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_NUM_REGISTER_SETS_IRQ; i++){
                ret[i] = skadi_init_alloc_allocate_aligned(sizeof(*ret[i]), SKADI_ALL_PERMISSIONS, false, SKADI_CALLER_TRAMPOLINE_ALIGNMENT);

                if(!ret[i]){
                    return 0;
                }
            }
            return (uintptr_t) ret;
        }
    }
#endif

    return (uintptr_t)skadi_resolve_special_symbol(symbol_name, current_extension_name, skadi_loader_current_subsystem_id);
}

typedef void (*skadi_loader_set_task_id_t)(uint32_t task_id);

void llext_free_symtable(struct llext *ext);

static long long unsigned int sum_text_size = 0, sum_data_size = 0, sum_rodata_size = 0, sum_bss_size = 0;

void skadi_loader_print_memory_summary(void){
    LOG_INF("Total subsystem sizes:\nText size: %llu\nData size: %llu\nROData size: %llu\nBSS size: %llu", 
        sum_text_size, sum_data_size, sum_rodata_size, sum_bss_size);
}

#ifdef CONFIG_PROFILING_PERF
static uintptr_t text_region_starts[SKADI_NUM_SUBSYSTEMS];
static size_t text_region_lengths[SKADI_NUM_SUBSYSTEMS];
static size_t number_subsystems;
#endif

bool skadi_loader_load_subsystem(const char *subsys_name, const uint8_t *subsys_elf_start_orig, size_t subsys_elf_bytes){
    struct llext_loader *loader;
    struct llext_load_param load_param = LLEXT_LOAD_PARAM_DEFAULT;
    struct llext *subsystem;
    int result;
    struct llext_buf_loader buf_loader =  LLEXT_BUF_LOADER(NULL, 0);; 
    int irq_key;
    const uint8_t *subsys_elf_start;

#ifdef CONFIG_SKADI_SUBSYSTEM_COMPRESSION

    uint8_t *lz4_buffer;
    size_t decompressed_size;
    LZ4F_dctx *dctx;
    size_t dstSize;
    size_t srcSize = subsys_elf_bytes;
    size_t lz4f_return;
    /* variable header size */
    LZ4F_errorCode_t context_create_ok = LZ4F_createDecompressionContext(&dctx, LZ4F_VERSION);
    LZ4F_frameInfo_t frame_info;

    if(context_create_ok){
        LOG_ERR("Could not prepare decompression context!");
        return false;
    }

    dstSize = srcSize;

    lz4f_return = LZ4F_getFrameInfo(dctx, &frame_info, subsys_elf_start_orig, &dstSize);
    /* header was read into context */
    subsys_elf_start_orig += dstSize;

    if (LZ4F_isError(lz4f_return)) {
		LOG_ERR("Could not get LZ4 frame info!");
		return -EIO;
	}

	if (!frame_info.contentSize) {
		LOG_ERR("No contentSize provided in LZ4 frame header!");

		return -EINVAL;
	}

    dstSize = frame_info.contentSize;

    lz4_buffer = skadi_allocator_alloc_rw(dstSize);

    __ASSERT_NO_MSG(lz4_buffer);
    if(!lz4_buffer){
        LZ4F_freeDecompressionContext(dctx);
        LOG_ERR("Could not allocate lz4 buffer of %zu bytes!", dstSize);
        return false;
    }


    decompressed_size = LZ4F_decompress(dctx, lz4_buffer, &dstSize, subsys_elf_start_orig, &srcSize,  NULL);

    if(decompressed_size || LZ4F_isError(decompressed_size)){
        LOG_ERR("Decompression indicates %zu!", decompressed_size);
        LZ4F_freeDecompressionContext(dctx);
        skadi_allocator_free(lz4_buffer);
        return false;
    }

    LZ4F_freeDecompressionContext(dctx);
    
    subsys_elf_start = lz4_buffer;

    subsys_elf_bytes = frame_info.contentSize;

#else
    subsys_elf_start = subsys_elf_start_orig;
#endif

    buf_loader.buf = subsys_elf_start;
    buf_loader.len = subsys_elf_bytes;

    if(skadi_loader_next_task_id == 0){
        LOG_ERR("Task ID overflow!");
#ifdef CONFIG_SKADI_SUBSYSTEM_COMPRESSION
         skadi_allocator_free(lz4_buffer);
#endif
        return false;
    }

    skadi_loader_current_subsystem_is_libc = strcmp("libc", subsys_name)==0;
    
    skadi_loader_current_subsystem_id = skadi_loader_get_task_id_for_subsystem(subsys_name);

    current_extension_name = subsys_name;

    LOG_DBG("Loading subsystem %s from input buffer at %p!",subsys_name, subsys_elf_start);


    loader = &buf_loader.loader;

    result = llext_load(loader, subsys_name, &subsystem, &load_param);
    if(result != 0){
        LOG_ERR("Could not load subsystem! Error %d (%s)",-result, strerror(-result));
#ifdef CONFIG_SKADI_SUBSYSTEM_COMPRESSION
         skadi_allocator_free(lz4_buffer);
#endif
        return false;
    }

    LOG_INF("Add subsystem symbols as follows in GDB (assuming \"scripts/skadi/.gdbinit\" was loaded):");
    LOG_INF("skadi_debug_subsystem %s %p %p %p %p",
            subsys_name, subsystem->mem[LLEXT_MEM_TEXT], subsystem->mem[LLEXT_MEM_DATA], subsystem->mem[LLEXT_MEM_RODATA], subsystem->mem[LLEXT_MEM_BSS]);

    LOG_INF("Generating set-task-id capabilities for exported functions for subsystem %s with task id %"PRIu32"!",subsys_name,skadi_loader_get_task_id_for_subsystem(subsys_name));
    skadi_loader_create_capabilities_for_exported_symbols(subsystem, skadi_loader_get_task_id_for_subsystem(subsys_name));

    LOG_INF("Calling initialization functions for extension %s!",subsys_name);

    // may need to use the function pointers in init already
    if(skadi_loader_init_subsystem(subsystem) == false){
        LOG_ERR("Could not initialize subsystem!");
#ifdef CONFIG_SKADI_SUBSYSTEM_COMPRESSION
         skadi_allocator_free(lz4_buffer);
#endif
        return false;
    }
    /* no IRQ when coming back from subsystem call - cannot properly handle timer interrupt! */
    irq_key = irq_lock();

    for(enum llext_mem mem_idx = LLEXT_MEM_TEXT; mem_idx < LLEXT_MEM_COUNT; mem_idx ++){
        if(subsystem->mem_on_heap[mem_idx]){
            /**
             * Two exceptions to task ID restriction:
             * - Can be completely disabled, usually used in SKADI_DEBUG mode.
             * - Can be disabled for the libc subsystem specifically.
             */
            bool do_restriction = !IS_ENABLED(CONFIG_SKADI_DISABLE_TASK_RESTRICTION_FOR_CODE_DATA) && !(IS_ENABLED(CONFIG_SKADI_LIBC_HAS_NO_TID_PROTECTION) && skadi_loader_current_subsystem_is_libc);
            skadi_restriction_t restriction = SKADI_TASK_ID_RESTRICTION(skadi_loader_get_task_id_for_subsystem(subsys_name), SKADI_DEVICE_ID_CPU, do_restriction ? SKADI_RESTRICTIONS_TASK_ID_BOUND : SKADI_RESTRICTIONS_NONE);
            skadi_permission_type_t permissions = SKADI_PERMISSION_READ | SKADI_PERMISSION_LOCKABLE | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS;

            if(!do_restriction){
                LOG_WRN("Task-id protection disabled for subsystem %s", subsys_name);
            }

            if(mem_idx == LLEXT_MEM_BSS || mem_idx == LLEXT_MEM_DATA || IS_ENABLED(CONFIG_SKADI_DISABLE_WRITE_PREVENTION_FOR_CODE_RO_DATA)){
                permissions |= SKADI_PERMISSION_WRITE;
            }
            // no more need to access the segment in the loader
            // setting all permissions to one does not enable any permission that was previously disabled; this is silently ignored
            // so by setting them to true, we are really keeping the initial value
            // we also use the opportunity to kick writable for everything but DATA and BSS
            if(skadi_cap_ops_restrict(subsystem->mem[mem_idx], restriction, 0, 0, permissions) == false){
                LOG_ERR("Could not add current-task-id restriction to subsystem's segment!");
                irq_unlock(irq_key);
#ifdef CONFIG_SKADI_SUBSYSTEM_COMPRESSION
         skadi_allocator_free(lz4_buffer);
#endif
                return false;
            }
        }
    }


    irq_unlock(irq_key);

    /* symbol table not useful any more - free to restore space */
    llext_free_symtable(subsystem);

    /* task-id restricted - cannot be shared with next subsystem */
    skadi_loader_cleanup_mmio_device_list();

    /* still used with init functions */
    skadi_loader_next_task_id++;

    LOG_INF("Subsystem %s loaded",subsys_name);

#ifdef CONFIG_PROFILING_PERF
    text_region_starts[number_subsystems] = (uintptr_t) subsystem->mem[LLEXT_MEM_TEXT];
    text_region_lengths[number_subsystems] = loader->sects[LLEXT_MEM_TEXT].sh_size;

    __ASSERT_NO_MSG(number_subsystems < SKADI_NUM_SUBSYSTEMS);

	if(number_subsystems < SKADI_NUM_SUBSYSTEMS){
		number_subsystems++;
	}
#endif

    if(IS_ENABLED(CONFIG_SKADI_LOADER_PRINT_SECT_SIZES)){
        for(enum llext_mem mem_idx = LLEXT_MEM_TEXT; mem_idx < LLEXT_MEM_COUNT; mem_idx++){
            const char *section_name = llext_mem_name_table[mem_idx];
            LOG_INF("Subsystem %s section %s size %llu", subsys_name, section_name, loader->sects[mem_idx].sh_size);
        }

        sum_text_size += loader->sects[LLEXT_MEM_TEXT].sh_size;
        sum_data_size += loader->sects[LLEXT_MEM_DATA].sh_size;
        sum_rodata_size += loader->sects[LLEXT_MEM_RODATA].sh_size;
        sum_bss_size += loader->sects[LLEXT_MEM_BSS].sh_size;
    }

#ifdef CONFIG_SKADI_SUBSYSTEM_COMPRESSION
    skadi_allocator_free(lz4_buffer);
#endif

    return true;
}

struct skadi_loader_iterate_param {
    const char *symbol_name;
    uintptr_t symbol_value;
};

static int iterate_check_symbol(struct llext *ext, void *arg){
    struct skadi_loader_iterate_param *param = (struct skadi_loader_iterate_param*) arg;
    uintptr_t symbol_val;

    symbol_val = (uintptr_t) llext_find_sym(&ext->exp_tab, param->symbol_name);

    if(symbol_val){
        LOG_DBG("Found symbol %s in llext %s", param->symbol_name, ext->name);
        param->symbol_value = symbol_val;
        return 1;
    }

    return 0;
    

}

uintptr_t skadi_loader_get_symbol(const char *symbol_name){
    struct skadi_loader_iterate_param param = {symbol_name, 0};
    if(!llext_iterate(iterate_check_symbol, &param)){
        LOG_WRN("Could not find symbol %s!",symbol_name);
        return 0;
    }

    return param.symbol_value;
}
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(uintptr_t, __skadi_loader_proxy_get_symbol, const char *symbol_name)
    return skadi_loader_get_symbol(symbol_name);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__skadi_loader_proxy_get_symbol)


struct skadi_loader_init_function_param {
    struct llext *minimum_llext;
    int current_minimum;
    enum init_level level;
};

static int iterate_check_init_fn(struct llext *ext, void *arg){
    struct skadi_loader_init_function_param *callback_param = arg;
    const void *get_pending_prio;

    get_pending_prio = llext_find_sym(&ext->exp_tab, "skadi_subsystem_get_pending_priority_callee_trampoline");

    if(get_pending_prio){
        int next_prio = skadi_subsystem_init_functions(callback_param->level, get_pending_prio);
        /* -1 is reserved value for nothing left to do */
        if(next_prio <= callback_param->current_minimum && next_prio >= 0){
            callback_param->current_minimum = next_prio;
            callback_param->minimum_llext = ext;
        }
    }

    return 0;

}


int skadi_loader_call_next_init_function(enum init_level level, int next_loader_prio){
    struct skadi_loader_init_function_param callback_param = { NULL, next_loader_prio, level};

    /* we have to go through all invocations */
    (void)llext_iterate(iterate_check_init_fn, &callback_param);

    if(callback_param.minimum_llext){
        /* found llext that is lower than the loader - call its next init function */
        const void *call_next_init_fn = llext_find_sym(&callback_param.minimum_llext->exp_tab, "skadi_subsystem_call_next_init_function_callee_trampoline");
        __ASSERT(call_next_init_fn != NULL, "Should be able to call init function when it is advertised by subsystem!");

        LOG_INF("Calling skadi subsystem initialization function for level %d subsystem %s",level, callback_param.minimum_llext->name);
        
        if(call_next_init_fn){
            int ok = skadi_subsystem_init_functions(callback_param.level, call_next_init_fn);
            if(ok != 0){
                LOG_WRN("Init function failed for llext %s!",callback_param.minimum_llext->name);
            }
            return 1; /* OK - called init fn from skadi loader */
        }
    }
    /* failed to call init fn */
    return 0;
    
}

#ifdef CONFIG_SKADI_SUBSYSTEM_PROVIDES_MAIN
int skadi_loader_call_main(int argc, char **argv){
    uintptr_t main_location = skadi_loader_get_symbol("main_callee_trampoline");

    if(main_location == 0){
        LOG_WRN("Could not locate main()!");
        return -EINVAL;
    }

    return skadi_subsystem_main(argc, argv, (void*) main_location);

}
#endif

#ifdef CONFIG_SKADI_EARLYCON
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ(int, ____skadi_vprintf_early, const char *format, va_list ap)
    printf("[Earlycon]");
    return vprintf(format, ap);
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(____skadi_vprintf_early)
#endif

#ifdef CONFIG_PROFILING_PERF
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS(skadi_perf_add_text_region, uintptr_t region_start, size_t region_length);
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_IMPL(skadi_perf_add_text_region, 2, uintptr_t region_start, size_t region_length);
    
    void skadi_loader_provide_perf_metadata(void){
        void (*add_text_region)(uintptr_t region_start, size_t region_length) = (void*)skadi_loader_get_symbol("__skadi_perf_add_text_region_callee_trampoline");

        __ASSERT_NO_MSG(add_text_region);

        skadi_subsystem_check_function_pointer(add_text_region, false, false);

        for(size_t subsystem = 0; subsystem < number_subsystems; subsystem++){
            LOG_INF("Adding text region %p+%zu",(void*)text_region_starts[subsystem], text_region_lengths[subsystem]);
            skadi_perf_add_text_region(text_region_starts[subsystem], text_region_lengths[subsystem], add_text_region);
        }
    }
#endif

__boot_func static int skadi_loader_init(void){
	SKADI_SUBSYSTEM_INITIALIZE_CALLER_TRAMPOLINE(skadi_loader_init_functions);
    SKADI_SUBSYSTEM_INITIALIZE_CALLER_TRAMPOLINE(skadi_subsystem_init_functions);
#ifdef CONFIG_SKADI_SUBSYSTEM_PROVIDES_MAIN
    SKADI_SUBSYSTEM_INITIALIZE_CALLER_TRAMPOLINE(skadi_subsystem_main);
#endif
#ifdef CONFIG_SKADI_EARLYCON
    ____skadi_vprintf_early_register_init_function();
#endif

    __skadi_loader_proxy_get_symbol_register_init_function();

    skadi_loader_create_capabilities_for_exported_symbols_main_binary();

    return 0;
}

SYS_INIT(skadi_loader_init, PRE_KERNEL_1, CONFIG_LOADER_SKADI_LOADER_INIT_PRIO);
