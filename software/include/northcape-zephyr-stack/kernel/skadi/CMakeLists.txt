list(APPEND kernel_files
  skadi/skadi_loader_init_fn_callee_trampoline.S
  skadi/skadi_init.c
  skadi/skadi_init_alloc.c
  skadi/skadi_plic_stub_noloader.c
  skadi/skadi_string_functions.c
  )

  
  if(CONFIG_SKADI_DEBUG_MODULE_DRIVER)
    list(APPEND kernel_files skadi/skadi_debug_module_driver.c)
  endif()
  
  if(CONFIG_SKADI_LOADER)
    list(APPEND kernel_files
      skadi/skadi_loader.c
      skadi/skadi_loader_common.c
    )
  endif()


  add_compile_options(-DNO_THREADS_IN_CALLEE_TRAMPOLINE)
