#ifndef SKADI_LOADER_H
#define SKADI_LOADER_H
    #include <stdbool.h>
    #include <stddef.h>
    #include <stdint.h>

    #include <zephyr/llext/llext.h>
    #include <zephyr/skadi/skadi_ops_constants.h>

#ifdef CONFIG_SKADI_LOADER

    #ifdef SKADI_SUBSYSTEM
        #include <zephyr/skadi/skadi_subsystem.h>
        SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(uintptr_t, __skadi_loader_get_symbol, const char *symbol_name);

        static inline uintptr_t skadi_loader_get_symbol(const char *symbol_name){
            size_t len = strlen(symbol_name) + 1;
            const char *derived_sym_name = skadi_cap_ops_derive_arg_ro(symbol_name, len);
            uintptr_t ret;
            bool drop_ok;

            ret = __skadi_loader_get_symbol(derived_sym_name);

            drop_ok = skadi_cap_ops_drop(derived_sym_name);

            __ASSERT_NO_MSG(drop_ok);

            return ret;
        }
    #else
        
        #define SKADI_LOADER_CALL_MAX_FUNCTION_NAME_LENGTH_BYTES 64

        // subsystem initialization function
        // MUST be defined for each subsystem
        typedef bool (*skadi_subsystem_init_t)(uint32_t task_id);

        bool skadi_loader_load_subsystem(const char *subsys_name, const uint8_t *subsys_elf_start, size_t subsys_elf_bytes);

        uintptr_t skadi_loader_get_symbol(const char *symbol_name);
        
        /**
         * @brief Find and call next init function from skadi subsystem.
         * @param level current run level
         * @param next_loader_prio priority of next init function from loader / main binary
         * @return <0 for error, 0 for nothing called, 1 for called
         */
        int skadi_loader_call_next_init_function(enum init_level level, int next_loader_prio);

        /**
         * Locates and invokes main() function from subsystems (if defined).
         */
        int skadi_loader_call_main(int argc, char **argv);
        
        /**
         * Prints a summary of allocated memory to the disk.
         */
        void skadi_loader_print_memory_summary(void);
    #endif
#endif
        /**
         * Resolve special symbols like MMIO, scheduler hook.
         */
        void *skadi_resolve_special_symbol(const char *name, const char *ext_name, skadi_task_id_t skadi_loader_current_subsystem_id);
        /**
         * Kick device cache
         */
        void skadi_loader_cleanup_mmio_device_list(void);

        /**
          * @brief Relocates exported subsystem calls from a subsystem into set-task-id segments.
         */
        void skadi_loader_create_capabilities_for_exported_symbols(struct llext *subsystem, skadi_task_id_t task_id_in);

        /**
          * @brief Relocates exported subsystem calls from loader and "main zephyr" into set-task-id segments.
          */
        void skadi_loader_create_capabilities_for_exported_symbols_main_binary(void);
#endif
