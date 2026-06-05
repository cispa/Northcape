#include <stdlib.h>

#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/skadi/skadi_ops_driver.h>
#include <zephyr/skadi/skadi_subsystem.h>



#include <zephyr/logging/log.h>
LOG_MODULE_REGISTER(skadi_llext_relocs, CONFIG_SKADI_LOG_LEVEL);

#include <zephyr/llext/llext.h>

#define SKADI_LOADER_MAX_SYMBOL_NAME_LEN 256


void skadi_loader_handle_relocated_symbol(const char *name, void *symbol){
    ARG_UNUSED(name);
    ARG_UNUSED(symbol);
}

static void skadi_loader_relocate_function(struct llext_symbol *current_symbol, struct llext_symtable *symtable, const char *subsystem_name, skadi_task_id_t task_id){
    size_t function_bytes;
    const void *end_addr, *function_ptr;
    void* derived_cap;
    bool derive_ok;
    const char *end_well_known_name;

    char symbol_tmp[SKADI_LOADER_MAX_SYMBOL_NAME_LEN];
    const char *const callee_trampoline_end = "callee_trampoline";

    skadi_restriction_t restriction = SKADI_TASK_ID_RESTRICTION(task_id, SKADI_DEVICE_ID_CPU, SKADI_RESTRICTIONS_SET_TASK_ID);

    /* we only create set-task-id tokens for exported functions */
    /* by convention, these end in callee_trampoline */
    end_well_known_name = strstr(current_symbol->name,callee_trampoline_end);

    if(end_well_known_name != NULL && end_well_known_name[strlen(callee_trampoline_end)] == '\0'){
        // symbol name has end marker - process it when we reach the start marker
        LOG_DBG("Processing exported symbol %s at %p!",current_symbol->name, current_symbol->addr);
    }
    else{
        LOG_DBG("Skipping exported symbol %s at %p!",current_symbol->name, current_symbol->addr);
        return;
    }

    (void) strncpy(symbol_tmp,current_symbol->name,sizeof(symbol_tmp));

    symbol_tmp[sizeof(symbol_tmp)-1] = '\0';

    (void) strncat(symbol_tmp, "_end", sizeof(symbol_tmp)-1);

    symbol_tmp[sizeof(symbol_tmp)-1] = '\0';
    
    end_addr = llext_find_sym(symtable,symbol_tmp);

    if(end_addr == NULL){
        LOG_ERR("Could not find end address %s for symbol %s", symbol_tmp, current_symbol->name);
        k_panic();
    }

    if(end_addr < current_symbol->addr){
        LOG_ERR("Invalid end addr %p (%s) for symbol %p (%s)", end_addr, symbol_tmp, current_symbol->addr, current_symbol->name);
        k_panic();
    }

    function_bytes = (uintptr_t) end_addr - (uintptr_t) current_symbol->addr;

    if(skadi_get_capability_offset(current_symbol->addr) % 4 != 0){
        LOG_ERR("Invalid address of callee trampoline: %p", current_symbol->addr);
        k_panic();
    }

    derive_ok = skadi_cap_ops_derive_min_cap_type(end_addr, restriction, function_bytes, skadi_get_capability_offset(current_symbol->addr), SKADI_PERMISSION_READ | SKADI_PERMISSION_EXECUTE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS, IS_ENABLED(CONFIG_SKADI_TEXT_ALIGN_12_BIT) ? SKADI_CAPABILITY_TYPE_OFFSET_16_BIT : SKADI_CAPABILITY_TYPE_OFFSET_8_BIT, &derived_cap);

    if(!derive_ok || derived_cap == 0){
        LOG_ERR("Could not derive capability for exported symbol callee trampoline!");
        k_panic();
    }

    current_symbol->addr = derived_cap;

    // subsystem itself needds to know the value of the allocated trampoline
    // it might use it for passing function pointers to its own exported calls around
    (void) strncpy(symbol_tmp,current_symbol->name,sizeof(symbol_tmp));

    symbol_tmp[sizeof(symbol_tmp)-1] = '\0';

    (void) strncat(symbol_tmp, "_function_pointer", sizeof(symbol_tmp)-1);

    symbol_tmp[sizeof(symbol_tmp)-1] = '\0';
    
    function_ptr = llext_find_sym(symtable,symbol_tmp);

    if(function_ptr == NULL){
        LOG_WRN("Could not find function pointer %s for symbol %s", symbol_tmp, current_symbol->name);
    }
    else{
        void **function_ptr_val = (void **) function_ptr;
        *function_ptr_val = derived_cap;
        LOG_DBG("Set function pointer %s for symbol %s at %p to %p", symbol_tmp, current_symbol->name, function_ptr_val, derived_cap);
    }

    skadi_loader_handle_relocated_symbol(current_symbol->name, derived_cap);
}

static void skadi_loader_relocate_data(struct llext_symbol *current_symbol, const char *subsystem_namem, bool readonly){
    size_t device_size = current_symbol->size;
    void *derived_cap;
    bool derive_ok;
    const char *start_well_known_name, *end_well_known_name;
    const skadi_restriction_t restriction = SKADI_NO_RESTRICTION;
    struct device *dev = (struct device *)current_symbol->addr;
    struct device_state *state;
    bool is_device = false;

    const char *const device_symbol_name_start = "__device_dts_ord_";
    const char *const function_pointer_name_end = "_callee_trampoline_function_pointer";

    /* exported devices follow a naming convention with a prefix and a device tree id */
    start_well_known_name = strstr(current_symbol->name,device_symbol_name_start);

    /* callee trampoline function pointers have a well-known suffix and are ignored */
    end_well_known_name = strstr(current_symbol->name, function_pointer_name_end);

    if(start_well_known_name != NULL && start_well_known_name == current_symbol->name){
        /* matches the device naming convention - we can assume that this is a device */
        LOG_DBG("Processing exported symbol %s at %p as device export!",current_symbol->name, current_symbol->addr);
        is_device = true;
    }
    else{
        LOG_DBG("Treating exported symbol %s at %p as non-device!",current_symbol->name, current_symbol->addr);
    }

    if(end_well_known_name != NULL && end_well_known_name[strlen(function_pointer_name_end)] == '\0'){
        /* callee trampoline function pointer: ignored! */
        return;
    }

    if(skadi_get_capability_offset(current_symbol->addr) % sizeof(void*) != 0){
        LOG_ERR("Invalid address of data: %p", current_symbol->addr);
        k_panic();
    }
    
    derive_ok = skadi_cap_ops_derive(current_symbol->addr, restriction, device_size, skadi_get_capability_offset(current_symbol->addr), readonly ? SKADI_PERMISSION_READ | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS : SKADI_PERMISSION_READ | SKADI_PERMISSION_WRITE | SKADI_PERMISSION_IRQ_ACCESSIBLE | SKADI_PERMISSION_CACHEABLE_TLB | SKADI_PERMISSION_CACHEABLE_ACCESS,  &derived_cap);

    if(!derive_ok || derived_cap == NULL){
        LOG_ERR("Could not derive capability for exported symbol callee trampoline!");
        k_panic();
    }

    LOG_DBG("Relocated data symbol %s at %p size %zu is readonly %d", current_symbol->name, derived_cap, current_symbol->size, readonly);

    current_symbol->addr = derived_cap;

    if(is_device){

        state = dev->state;

        state = skadi_cap_ops_derive_arg(state, sizeof(*state));

        __ASSERT_NO_MSG(state);

        if(!state){
            LOG_ERR("Could not derive device state!");
            /* might not be used... */
            return;
        }

        dev->state = state;
    }

    skadi_loader_handle_relocated_symbol(current_symbol->name, derived_cap);
}

static enum llext_mem skadi_loader_get_section_for_symbol(const struct llext_symbol *symbol, const struct llext *ext){
    enum llext_mem ret;

    for(ret = LLEXT_MEM_TEXT; ret < LLEXT_MEM_COUNT; ret ++){
        if(skadi_is_same_capability(ext->mem[ret], symbol->addr)){
            break;
        }   
    }
    /* should always be one of the sections */
    __ASSERT(ret != LLEXT_MEM_COUNT, "Could not find section for symbol %s (%p)!", symbol->name, symbol->addr);

    return ret;
}

void skadi_loader_symbol_resolved_cb(struct llext *subsystem, const char *symbol_name, const void *symbol_value){
#if defined(CONFIG_SKADI_CHECK_SUBSYSTEM_CALL_ID)
    char *symbol_name_buf = skadi_allocator_alloc_rw(strlen(symbol_name)+strlen("_callee_trampoline_exp_task_id")+1);
    const void *symbol_val;
    uint32_t *task_out;
    __ASSERT_NO_MSG(symbol_name_buf);
    if(!symbol_name_buf){
        LOG_ERR("ENOMEM!");
        return;
    }
    /* save due to construction */
    strcpy(symbol_name_buf, symbol_name);
    strcat(symbol_name_buf, "_exp_task_id");

    symbol_val = llext_find_sym(&subsystem->sym_tab, symbol_name_buf);
    skadi_allocator_free(symbol_name_buf);
    if(!symbol_val){
        LOG_DBG("Could not find task ID symbol for imported symbol %s", symbol_name);
        return;
    }
    task_out = (uint32_t*)symbol_val;
    *task_out = skadi_cap_ops_inspect_get_tid(symbol_value);
    LOG_INF("Symbol %s task ID is %"PRIu32" (%p)", symbol_name, *task_out, task_out);
#else
    ARG_UNUSED(subsystem);
    ARG_UNUSED(symbol_name);
    ARG_UNUSED(symbol_value);
#endif
}

/**
 * @brief Relocates exported subsystem calls from a subsystem into set-task-id segments.
 */
void skadi_loader_create_capabilities_for_exported_symbols(struct llext *subsystem, skadi_task_id_t task_id_in){
    struct llext_symtable *symtable = &subsystem->exp_tab;
    void *llext_sym;


    // assume that each symbol actually is exported in pairs: one signifies the beginning, the other the end
    for(size_t i = 0; i < symtable->sym_cnt; i++){
        enum llext_mem section = skadi_loader_get_section_for_symbol(&symtable->syms[i], subsystem);
        if(i == symtable->sym_cnt + 1){
            break;
        }

        switch(section){
            case LLEXT_MEM_TEXT:

                skadi_loader_relocate_function(&symtable->syms[i], symtable, subsystem->name, task_id_in);
                break;
            
            case LLEXT_MEM_DATA:
            case LLEXT_MEM_RODATA:
            case LLEXT_MEM_BSS:

                skadi_loader_relocate_data(&symtable->syms[i], subsystem->name, section == LLEXT_MEM_RODATA);

            default:
                /* other sections like BSS just ignored */
                if(section == LLEXT_MEM_COUNT){
                    LOG_WRN("Could not find section for symbol %s - not relocating!", symtable->syms[i].name);
                }
                break;
        }

        
    }
    symtable = &subsystem->sym_tab;
    /* still writable - restrictions to be applied later, so we can cast the const away */
    llext_sym = (void *) llext_find_sym(symtable, "_skadi_current_subsystem_id");
    if(llext_sym != 0){
        uint32_t *task_id = (uint32_t *)llext_sym;
        *task_id = task_id_in;
    }
    else{
        LOG_WRN("Could not find symbol for subsystem task ID in subsystem %s!",subsystem->name);
    }
}


static const char * const skadi_loader_main_binary_name = "main_binary";

/**
 * @brief Relocates exported subsystem calls from loader and "main zephyr" into set-task-id segments.
 */
void skadi_loader_create_capabilities_for_exported_symbols_main_binary(void){
    const char *const end_symbol_terminator = "callee_trampoline";
    const char *const device_prefix = "__device_dts_ord_";
    const char *end_well_known_name;

    // exported symbols from us are included in a special section
    STRUCT_SECTION_FOREACH(llext_const_symbol, current_symbol) {
        LOG_DBG("Zephyr main binary exports symbol %s!", current_symbol->name);

        end_well_known_name = strstr(current_symbol->name,end_symbol_terminator);

        if(end_well_known_name != NULL && end_well_known_name[strlen(end_symbol_terminator)] == '\0'){
            // symbol name has end marker - process it when we reach the start marker
            LOG_DBG("Relocating main zephyr binary symbol %s at %p!",current_symbol->name, current_symbol->addr);
            // TODO this works as long as the section is writable
            skadi_loader_relocate_function((struct llext_symbol*) current_symbol, NULL, skadi_loader_main_binary_name, SKADI_TASK_ID_LOADER);   
        }

        end_well_known_name = strstr(current_symbol->name, device_prefix);

        if(end_well_known_name != NULL && end_well_known_name == current_symbol->name){
            /* TODO assume read-only */
            skadi_loader_relocate_data((struct llext_symbol*) current_symbol, skadi_loader_main_binary_name, true);
        }
	}                                                                                                                       
}


