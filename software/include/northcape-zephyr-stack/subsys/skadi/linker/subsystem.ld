SECTIONS {
    # workaround to force ld to update debug symbols
    .text : {
        KEEP(*(SORT_BY_NAME(.text*)));
    }

    # this creates the initialization-related sections and symbols
    initlevel :
    {
        __init_start = .;
        __init_EARLY_start = .; KEEP(*(SORT(.z_init_EARLY?_*))); KEEP(*(SORT(.z_init_EARLY??_*)));
        __init_PRE_KERNEL_1_start = .; KEEP(*(SORT(.z_init_PRE_KERNEL_1?_*))); KEEP(*(SORT(.z_init_PRE_KERNEL_1??_*)));
        __init_PRE_KERNEL_2_start = .; KEEP(*(SORT(.z_init_PRE_KERNEL_2?_*))); KEEP(*(SORT(.z_init_PRE_KERNEL_2??_*)));
        __init_POST_KERNEL_start = .; KEEP(*(SORT(.z_init_POST_KERNEL?_*))); KEEP(*(SORT(.z_init_POST_KERNEL??_*)));
        __init_APPLICATION_start = .; KEEP(*(SORT(.z_init_APPLICATION?_*))); KEEP(*(SORT(.z_init_APPLICATION??_*)));
        __init_SMP_start = .; KEEP(*(SORT(.z_init_SMP?_*))); KEEP(*(SORT(.z_init_SMP??_*)));
        __init_end = .;
        __deferred_init_list_start = .;
        KEEP(*(.z_deferred_init*))
        __deferred_init_list_end = .;
    }

    # we need these special symbols for iterating the subsystems
    net_if_area : SUBALIGN(8) { 
        _net_if_list_start = .;
        KEEP(*(SORT_BY_NAME(._net_if.static.*)));
        _net_if_list_end = .; 
    }

    # we need these special symbols for iterating the buffers
    net_buf_pool_area : SUBALIGN(8) { 
        _net_buf_pool_list_start = .; 
        KEEP(*(SORT_BY_NAME(._net_buf_pool.static.*)));
        _net_buf_pool_list_end = .; 
    }

    # we need these special symbols for iterating the network handler list
    net_mgmt_event_static_handler_area : SUBALIGN(8) {
        _net_mgmt_event_static_handler_list_start = .;
         KEEP(*(SORT_BY_NAME(._net_mgmt_event_static_handler.static.*)));
         _net_mgmt_event_static_handler_list_end = .; 
    }

    # we need these special symbols for iterating the socket list
    net_socket_register_area : SUBALIGN(8) { 
        _net_socket_register_list_start = .;
        KEEP(*(SORT_BY_NAME(._net_socket_register.static.*)));
        _net_socket_register_list_end = .; 
    }

    # we need these special symbols for iterating the socket descriptors
    net_socket_service_desc_area : SUBALIGN(8) {
         _net_socket_service_desc_list_start = .;
         KEEP(*(SORT_BY_NAME(._net_socket_service_desc.static.*)));
         _net_socket_service_desc_list_end = .;
    }

    # we need these special symbols for iterating shell commands
    shell_area : SUBALIGN(8) {
        _shell_list_start = .;
        KEEP(*(SORT_BY_NAME(._shell.static.*)));
        _shell_list_end = .;
    }

    shell_root_cmds_area : SUBALIGN(8) {
        _shell_root_cmds_list_start = .;
        KEEP(*(SORT_BY_NAME(._shell_root_cmds.static.*)));
        _shell_root_cmds_list_end = .;
    }

    shell_subcmds_area : SUBALIGN(8) {
        _shell_subcmds_list_start = .;
        KEEP(*(SORT_BY_NAME(._shell_subcmds.static.*)));
        _shell_subcmds_list_end = .;
    }

    shell_dynamic_subcmds_area : SUBALIGN(8) {
        _shell_dynamic_subcmds_list_start = .;
        KEEP(*(SORT_BY_NAME(._shell_dynamic_subcmds.static.*)));
        _shell_dynamic_subcmds_list_end = .;
    }

    # we need these special symbols to iterate devices
    device_area : SUBALIGN(8) {
        _device_list_start = .;
        KEEP(*(SORT(._device.static.*_?_*)));
        KEEP(*(SORT(._device.static.*_??_*)));
        _device_list_end = .;
    }

    k_heap_area : SUBALIGN(8) {
        _k_heap_list_start = .;
        *(SORT_BY_NAME(._k_heap.static.*));
        _k_heap_list_end = .;
    }

    k_mem_slab_area : SUBALIGN(8) {
        _k_mem_slab_list_start = .;
        *(SORT_BY_NAME(._k_mem_slab.static.*));
        _k_mem_slab_list_end = .;
    }

    _static_thread_data_area : SUBALIGN(8) {
        __static_thread_data_list_start = .;
        KEEP(*(SORT_BY_NAME(.__static_thread_data.static.*)));
        __static_thread_data_list_end = .;
    }

    # we need to merge all of the SHT_NOBIT sections; otherwise, the loader will complain
    .bss : SUBALIGN(8) {
        *(.bss .bss.*)
        *(.noinit .noinit.*)
        *(.tbss .tbss.*) # libc-specific
    }
}
