if(CONFIG_SKADI_OS)
    # list will hold the executables of added subsystems
    # we will extract imported/exported symbols and topologically sort the subsystems
    # this will give us an initialization sequence
    set(SUBSYSTEM_LIST "")

    # create a skadi subsystem
    # options
    # NO_LIBRARY: do not provide skadi subsystem runtime library (includes things like initialization of callee stacks etc.)
    # NO_ISOLATED_LIBC: jump directly into libc without using subsystem call isolation
    # FPU: the subsystem uses the FPU

    # start count at 1, for main, which is not counted
    set_property(GLOBAL PROPERTY num_subsystems 1)
    set_property(GLOBAL PROPERTY skadi_subsystems "")

    function(create_skadi_subsystem_custom_sources)
        cmake_parse_arguments(
            PARSED_ARGS # prefix
            "NO_LIBRARY;NO_ISOLATED_LIBC;NO_YIELD;FPU;NO_LOCAL_CLOCK" # boolean args
            "EXT_NAME;APP" # scalar arguments
            "SRCS;EXTRA_CPPFLAGS;EXTRA_LINK_FLAGS" # array arguments
            ${ARGN}
        )

        if(NOT CONFIG_SKADI_LOADER)
            return()
        endif()

        if(NOT PARSED_ARGS_EXT_NAME)
            message(FATAL_ERROR "EXT_NAME missing!")
        endif()

        if(NOT PARSED_ARGS_APP)
            message(FATAL_ERROR "APP missing!")
        endif()

        set(ext_name ${PARSED_ARGS_EXT_NAME})
        set(app ${PARSED_ARGS_APP})
        set(libc_compile_flags "")
        # skadi_sched_yield.S provides utility function that is used by all subsystems
        # skadi_library.c contains some library functions and data
        # skadi_ops_driver.c contains the operations module routines

        if(NOT ${PARSED_ARGS_NO_LIBRARY})
            set(ext_src ${PARSED_ARGS_SRCS} ${ZEPHYR_BASE}/subsys/skadi/library/skadi_library.c ${ZEPHYR_BASE}/lib/hash/hash_map_sc.c ${ZEPHYR_BASE}/lib/hash/hash_func32_murmur3.c ${ZEPHYR_BASE}/kernel/skadi/skadi_string_functions.c ${ZEPHYR_BASE}/subsys/skadi/library/skadi_libc.c ${ZEPHYR_BASE}/include/zephyr/skadi/subsystems/scheduler/skadi_sched_yield.S ${ZEPHYR_BASE}/subsys/logging/log_minimal.c)
            if(CONFIG_SKADI_LIBRARY_LOCAL_ALLOCATOR)
                set(ext_src ${ext_src} ${ZEPHYR_BASE}/subsys/skadi/library/skadi_local_allocator.c)
            endif()
            if(CONFIG_SKADI_LIBC_INLINE)
                set(libc_prefix ${ZEPHYR_PICOLIBC_MODULE_DIR}/newlib/libc)
                set(libc_files 
                    ${libc_prefix}/string/strncpy.c
                    ${libc_prefix}/string/strncasecmp.c
                    ${libc_prefix}/string/strncmp.c
                    ${libc_prefix}/stdlib/strtol.c
                    ${libc_prefix}/stdlib/strtoll.c
                    ${libc_prefix}/stdlib/strtoul.c
                    ${libc_prefix}/stdlib/strtoull.c
                    ${libc_prefix}/string/strstr.c
                    ${libc_prefix}/string/strchr.c
                    ${libc_prefix}/string/strrchr.c
                    ${libc_prefix}/string/strerror.c
                    ${libc_prefix}/string/memcmp.c
                    ${libc_prefix}/machine/riscv/memset.S
                    ${libc_prefix}/string/memchr.c
                    ${libc_prefix}/string/memmove.c
                    ${libc_prefix}/locale/locale.c
                    ${libc_prefix}/ctype/isspace_l.c
                    ${libc_prefix}/stdlib/mbtowc_r.c
                    ${libc_prefix}/stdlib/wctomb_r.c
                    ${ZEPHYR_BASE}/subsys/skadi/libc/skadi_library_subsystem.c
                )
                set(ext_src ${ext_src} ${libc_files})
                set(libc_compile_flags ${libc_compile_flags} "-D_ZEPHYR_SOURCE" -include${libc_prefix}/include/sys/_locale.h)
            endif()
            if(CONFIG_SKADI_LIBRARY_LOCAL_CLOCK)
                if(${PARSED_ARGS_NO_LOCAL_CLOCK})
                    message("Local clock disabled for subsystem ${ext_name}")
                else()
                    set(ext_src ${ext_src} ${ZEPHYR_BASE}/subsys/skadi/library/skadi_local_clock.c ${ZEPHYR_BASE}/subsys/skadi/library/skadi_local_clock.S)
                endif()
            endif()
        else()
            # a minimal library with the minimum necessary init functions and data structures
            set(ext_src ${PARSED_ARGS_SRCS} ${ZEPHYR_BASE}/subsys/skadi/library/skadi_dummy_library.c  ${ZEPHYR_BASE}/kernel/skadi/skadi_string_functions.c)
        endif()

        if(${PARSED_ARGS_NO_YIELD})
            message("Assuming extension ${ext_name} is never invoked with timer interrupts enabled!")
            set(ext_src ${ext_src} ${ZEPHYR_BASE}/subsys/skadi/library/skadi_dummy_sched_yield.S)
        endif()

        set(ext_src ${ext_src} ${ZEPHYR_BASE}/soc/openhwgroup/cv64a6/cv64a6/soc_cache_management.c ${ZEPHYR_BASE}/lib/os/assert.c)
        if(CONFIG_SOC_SERIES_CV64A6_PROVIDE_TEST_POWEROFF)
            set(ext_src ${ext_src} ${ZEPHYR_BASE}/soc/openhwgroup/cv64a6/cv64a6/soc_poweroff.c ${ZEPHYR_BASE}/lib/os/poweroff.c)
        endif()
        if(CONFIG_SOC_SERIES_CV64A6_PROVIDE_FPGA_POWEROFF)
            set(ext_src ${ext_src} ${ZEPHYR_BASE}/soc/openhwgroup/cv64a6/cv64a6/soc_poweroff_fpga.c ${ZEPHYR_BASE}/lib/os/poweroff.c)
        endif()

        # this header is sometimes included in all files; it is not compatible with assembly language
        # this prevents the header from being loaded here
        SET_SOURCE_FILES_PROPERTIES( ${ZEPHYR_BASE}/include/zephyr/skadi/subsystems/scheduler/skadi_sched_yield.S PROPERTIES COMPILE_FLAGS -DSKADI_ERRNO_H)

        message("Creating skadi subsystem ${ext_name} for application ${app} from sources ${ext_src} with extra CPP flags ${PARSED_ARGS_EXTRA_CPPFLAGS} extra LD flags ${PARSED_ARGS_EXTRA_LINK_FLAGS}")

        set(ext_bin ${ZEPHYR_BINARY_DIR}/${ext_name}.llext)
        set(ext_bin_intermediate ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}.notrampolines.llext)
        set(ext_inc ${ZEPHYR_BINARY_DIR}/include/generated/${ext_name}_ext.inc)

        set(c_model_flags "-mcmodel=large" ${PARSED_ARGS_EXTRA_CPPFLAGS} -include ${ZEPHYR_BASE}/include/zephyr/skadi/skadi_errno.h)
        if(CONFIG_FPU)
            set(abi_flags "-march=rv64imafdc_zicsr_zifencei_zba_zbb_zbc_zbs" "-mabi=lp64d" "-mstrict-align")
        else()
            set(abi_flags "-march=rv64imac_zicsr_zifencei_zba_zbb_zbc_zbs" "-mabi=lp64" "-mstrict-align")
        endif()

        add_llext_target(${ext_name}_ext
            OUTPUT  ${ext_bin_intermediate}
            SOURCES ${ext_src}
        )

        set(EXT_OBJECTS $<FILTER:$<TARGET_OBJECTS:${ext_name}_ext_llext_lib>,EXCLUDE,"_caller_trampolines">)

        add_custom_command(
            OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}_caller_trampolines.c
            COMMAND ${PYTHON_EXECUTABLE} ${ZEPHYR_BASE}/scripts/skadi/check_llext_symbols_resolved.py 
                --trampolines-out ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}_caller_trampolines.c
                --generate-caller-trampolines \"${EXT_OBJECTS}\"
            DEPENDS ${ZEPHYR_BASE}/scripts/skadi/check_llext_symbols_resolved.py ${EXT_OBJECTS}
        )

        # final version of the immediate, with trampolines
        add_llext_target(${ext_name}_ext_final
            OUTPUT  ${ext_bin}
            SOURCES ${ext_src} ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}_caller_trampolines.c
        )


        if(${PARSED_ARGS_NO_ISOLATED_LIBC})
            message(WARNING "LIBC is not protected for subsystem" ${ext_name})
            set(libc_isolation_flags "-DSKADI_SUBSYSTEM_NO_PROTECTED_LIBC")
        endif()

        if(${PARSED_ARGS_FPU})
            if(CONFIG_FPU)
                message(INFO "Enabling FPU for subsystem" ${ext_name})
                set(fpu_flags "-DSKADI_SUBSYSTEM_HAS_FPU")
                set(fpu_linkflags "")
            else()
                message("No hard FPU - not enabling HW FPU support for subsystem ${ext_name}! Linking soft float support library instead.")
                if(NOT ${PARSED_ARGS_NO_LIBRARY})
                    set(fpu_linkflags "-Wl,--whole-archive" "-Wl,-lskadi-float")
                    set(fpu_flags "")
                else()
                    message("Assuming libc includes libgcc anyway")
                    set(fpu_flags "")
                    set(fpu_linkflags "")
                endif()
            endif()
        else()
            set(fpu_flags "")
            set(fpu_linkflags "")
        endif()

        

        # linker relaxations are currently not implemented in the loader
        # they are crucial for alignment relocations:
        # R_RISCV_ALIGN expects us to move an address or scalar to where the compiler inserted
        # a number of padding bytes
        # -fno-zero-initialized-in-bss prevents overlap between data and bss
        # -fno-data-sections prevents GCC from including multiple .bss sections,
        # which are currently not supported in llext
        # -fno-jump-tables solves an issue with switch statements: for large switch statements,
        # GCC generates a jump table and performs a lookup of the switch key in it.
        # for some reason, the relocation it emits for the jump table appears to be 32-bit
        # in skadi, this is too small to fit the distance between .rodata and .text
        # so we have to disable jump tables and implement switches with branches...
        set(llext_extra_cflags "-mno-relax" "-Wl,--sort-section=name" "-fno-data-sections" "-fno-jump-tables" "-fipa-icf")

        if(CONFIG_PROFILING_PERF)
            # need frame pointer for figuring out where we are
            set(llext_extra_cflags "${llext_extra_cflags}" "-fno-omit-frame-pointer")
        endif()

        set(llext_link_options  ${abi_flags} ${c_model_flags} ${llext_extra_cflags}  ${PARSED_ARGS_EXTRA_LINK_FLAGS} -T ${ZEPHYR_BASE}/subsys/skadi/linker/subsystem.ld ${fpu_linkflags})
        set(llext_compile_options ${abi_flags} ${c_model_flags} -ffunction-sections -fdata-sections ${llext_extra_cflags} ${fpu_flags} "-DSKADI_SUBSYSTEM" ${libc_isolation_flags} -include${ZEPHYR_BASE}/include/zephyr/skadi/stdio/skadi_stdio.h ${libc_compile_flags})

        if(CONFIG_LLEXT_SYMBOL_GC)
            # all symbols not explicitly exported can be GCed
            set(llext_compile_options ${llext_compile_options} -fvisibility=hidden)
            # GC superfluous functions and globals
            set(llext_link_options ${llext_link_options} 
                -Wl,--gc-sections
                -Wl,--gc-keep-exported
            )
        endif()

        llext_link_options(${ext_name}_ext ${llext_link_options})
        llext_compile_options(${ext_name}_ext ${llext_compile_options})
        llext_link_options(${ext_name}_ext_final ${llext_link_options})
        llext_compile_options(${ext_name}_ext_final ${llext_compile_options})

        set(debug_dir ${CMAKE_BINARY_DIR}/debug_syms)

        add_llext_command(TARGET ${ext_name}_ext_final PRE_BUILD COMMAND ${CMAKE_COMMAND} -E make_directory ${debug_dir})

        # llext command has a race condition and does not work all the time
        # so create debug symbols after everything was compiled
        add_custom_target(${ext_name}_debug_symbols ALL COMMAND ${CMAKE_OBJCOPY} --only-keep-debug ${ext_bin} ${debug_dir}/${ext_name}.debug DEPENDS  app BYPRODUCTS ${debug_dir}/${ext_name}.debug)

        # debug sections in the included file are useless for skadi and can be removed
        # debugger can use symbols from .debug file created above
        # strip-unneeded removes other local symbols that are not strictly required for relocation, further reducing file size
        add_custom_target(${ext_name}_stripped ALL COMMAND ${CMAKE_STRIP} --strip-debug --strip-unneeded ${ext_bin} -o ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}.stripped BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}.stripped DEPENDS ${ext_name}_ext_final)

        if(CONFIG_SKADI_SUBSYSTEM_COMPRESSION)
            # high compression, overwrite if exists, include context size
            add_custom_target(${ext_name}_stripped_compressed ALL COMMAND lz4 --best --content-size -f ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}.stripped ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}._stripped_compressed BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}._stripped_compressed DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}.stripped)    
        endif()

        message("Debug files are available under ${debug_dir}/${ext_name}.debug")

        if(CONFIG_SKADI_SUBSYSTEM_COMPRESSION)
            generate_inc_file_for_target(app ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}._stripped_compressed ${ext_inc})
        else()
            generate_inc_file_for_target(app ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}.stripped ${ext_inc})
        endif()

        target_compile_options(app PUBLIC ${c_model_flags} ${abi_flags})
        target_link_options(app PUBLIC ${c_model_flags} ${abi_flags})

        if(CONFIG_SKADI_SUBSYSTEM_COMPRESSION)
            LIST(APPEND SUBSYSTEM_LIST ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}.stripped_compressed)
        else()
            LIST(APPEND SUBSYSTEM_LIST ${CMAKE_CURRENT_BINARY_DIR}/${ext_name}.stripped)
        endif()
        
        add_dependencies(create_skadi_subsystems_init_h_manifest ${ext_name}_ext_final)

        get_property(num_subsystems GLOBAL PROPERTY num_subsystems)
        MATH(EXPR num_subsystems "${num_subsystems}+1")
        set_property(GLOBAL PROPERTY num_subsystems ${num_subsystems})
        get_property(skadi_subsystems GLOBAL PROPERTY skadi_subsystems)
        list(APPEND skadi_subsystems ${ext_name})
        set_property(GLOBAL PROPERTY skadi_subsystems ${skadi_subsystems})
    endfunction()

    function(create_skadi_subsystem_eth_driver)
        cmake_parse_arguments(
            PARSED_ARGS # prefix
            "" # boolean args
            "EXT_NAME;APP;COMPATIBLE" # scalar arguments
            "SRCS;EXTRA_CPPFLAGS" # array arguments
            ${ARGN}
        )

        if(NOT CONFIG_SKADI_LOADER)
            return()
        endif()

        if(NOT PARSED_ARGS_COMPATIBLE)
            message(FATAL_ERROR "COMPATIBLE declaration for device tree missing!")
        endif()

        create_skadi_subsystem_custom_sources(EXT_NAME ${PARSED_ARGS_EXT_NAME} APP ${PARSED_ARGS_APP} SRCS ${PARSED_ARGS_SRCS} EXTRA_CPPFLAGS ${PARSED_ARGS_EXTRA_CPPFLAGS})

        file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/ethernet_subs")

        set(generated_file "${CMAKE_CURRENT_BINARY_DIR}/ethernet_subs/${PARSED_ARGS_EXT_NAME}_stub.c")
        execute_process(
            COMMAND
            ${PYTHON_EXECUTABLE}
            ${ZEPHYR_BASE}/scripts/skadi/generate_network_device_stub.py
            # extra arguments
            --outfile ${generated_file}
            --compatible ${PARSED_ARGS_COMPATIBLE}
            --subsystem-name ${PARSED_ARGS_EXT_NAME}
            --devtype ethernet
            RESULT_VARIABLE result
        )

        if(NOT result EQUAL 0)
            message(FATAL_ERROR "Generation of wrapper failed with result ${result}")
        endif()
        
        # when we are building with the loader disabled, the stub will not compile (and, frankly, work)
        skadi_extension_add_sources_ifdef(net CONFIG_SKADI_LOADER ${generated_file})
    endfunction()

    function(create_skadi_subsystem_mdio_driver)
        cmake_parse_arguments(
            PARSED_ARGS # prefix
            "" # boolean args
            "EXT_NAME;APP;COMPATIBLE" # scalar arguments
            "SRCS;EXTRA_CPPFLAGS" # array arguments
            ${ARGN}
        )

        if(NOT CONFIG_SKADI_LOADER)
            return()
        endif()

        if(NOT PARSED_ARGS_COMPATIBLE)
            message(FATAL_ERROR "COMPATIBLE declaration for device tree missing!")
        endif()

        create_skadi_subsystem_custom_sources(EXT_NAME ${PARSED_ARGS_EXT_NAME} APP ${PARSED_ARGS_APP} SRCS ${PARSED_ARGS_SRCS} EXTRA_CPPFLAGS ${PARSED_ARGS_EXTRA_CPPFLAGS})

        file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/mdio_subs")

        set(generated_file "${CMAKE_CURRENT_BINARY_DIR}/mdio_subs/${PARSED_ARGS_EXT_NAME}_stub.c")
        execute_process(
            COMMAND
            ${PYTHON_EXECUTABLE}
            ${ZEPHYR_BASE}/scripts/skadi/generate_network_device_stub.py
            # extra arguments
            --outfile ${generated_file}
            --compatible ${PARSED_ARGS_COMPATIBLE}
            --subsystem-name ${PARSED_ARGS_EXT_NAME}
            --devtype mdio
            RESULT_VARIABLE result
        )

        if(NOT result EQUAL 0)
            message(FATAL_ERROR "Generation of wrapper failed with result ${result}")
        endif()
        
        # when we are building with the loader disabled, the stub will not compile (and, frankly, work)
        skadi_extension_add_sources_ifdef(net CONFIG_SKADI_LOADER ${generated_file})
    endfunction()

    function(create_skadi_subsystem_phy_driver)
        cmake_parse_arguments(
            PARSED_ARGS # prefix
            "" # boolean args
            "EXT_NAME;APP;COMPATIBLE" # scalar arguments
            "SRCS;EXTRA_CPPFLAGS" # array arguments
            ${ARGN}
        )

        if(NOT CONFIG_SKADI_LOADER)
            return()
        endif()

        if(NOT PARSED_ARGS_COMPATIBLE)
            message(FATAL_ERROR "COMPATIBLE declaration for device tree missing!")
        endif()

        create_skadi_subsystem_custom_sources(EXT_NAME ${PARSED_ARGS_EXT_NAME} APP ${PARSED_ARGS_APP} SRCS ${PARSED_ARGS_SRCS} EXTRA_CPPFLAGS ${PARSED_ARGS_EXTRA_CPPFLAGS})

        file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/phy_subs")

        set(generated_file "${CMAKE_CURRENT_BINARY_DIR}/phy_subs/${PARSED_ARGS_EXT_NAME}_stub.c")
        execute_process(
            COMMAND
            ${PYTHON_EXECUTABLE}
            ${ZEPHYR_BASE}/scripts/skadi/generate_network_device_stub.py
            # extra arguments
            --outfile ${generated_file}
            --compatible ${PARSED_ARGS_COMPATIBLE}
            --subsystem-name ${PARSED_ARGS_EXT_NAME}
            --devtype phy
            RESULT_VARIABLE result
        )

        if(NOT result EQUAL 0)
            message(FATAL_ERROR "Generation of wrapper failed with result ${result}")
        endif()
        
        # when we are building with the loader disabled, the stub will not compile (and, frankly, work)
        skadi_extension_add_sources_ifdef(net CONFIG_SKADI_LOADER ${generated_file})
    endfunction()

    function(create_skadi_subsystem_main)
        cmake_parse_arguments(
            PARSED_ARGS # prefix
            "FPU" # boolean args
            "APP;" # scalar arguments
            "SRCS;EXTRA_CPPFLAGS" # array arguments
            ${ARGN}
        )

        if(NOT CONFIG_SKADI_LOADER)
            return()
        endif()
        
        if(${PARSED_ARGS_FPU})
            create_skadi_subsystem_custom_sources(EXT_NAME "main" APP ${PARSED_ARGS_APP} SRCS ${PARSED_ARGS_SRCS} EXTRA_CPPFLAGS ${PARSED_ARGS_EXTRA_CPPFLAGS} FPU)
        else()
            create_skadi_subsystem_custom_sources(EXT_NAME "main" APP ${PARSED_ARGS_APP} SRCS ${PARSED_ARGS_SRCS} EXTRA_CPPFLAGS ${PARSED_ARGS_EXTRA_CPPFLAGS})
        endif()

        # CMake refuses to compile the project unless it has *some* source files (however, they can be empty, as everything is in zephyr base + subsystems)
        set(dummy_file "${CMAKE_CURRENT_BINARY_DIR}/null.c")
        file(WRITE ${dummy_file} "/* nothing */")
        target_sources(${PARSED_ARGS_APP} PRIVATE ${dummy_file})

    endfunction()

    # the python script will find all of the llext targets automatically
    set(generated_header ${CMAKE_BINARY_DIR}/zephyr/include/generated/zephyr/skadi_subsystems_init.h)
    set(generated_manifest ${CMAKE_BINARY_DIR}/skadi/manifest.txt)
    add_custom_target(
        create_skadi_subsystems_init_h_manifest
        BYPRODUCTS ${generated_header} ${generated_manifest}
        COMMAND
        ${PYTHON_EXECUTABLE}
        ${ZEPHYR_BASE}/scripts/skadi/init_order.py
        # extra arguments
        --header_out ${generated_header}
        --sd_dir_out ${CMAKE_BINARY_DIR}/skadi/
        --llext-dir ${CMAKE_BINARY_DIR}/zephyr # output dir of subsystems
        DEPENDS ${SUBSYSTEM_LIST}
        WORKING_DIRECTORY ${ZEPHYR_BASE}/subsys/skadi/init
    )
    add_dependencies(zephyr create_skadi_subsystems_init_h_manifest)


    function(create_skadi_subsystem ext_name app)
        set(ext_src src/${ext_name}.c)

        if(NOT CONFIG_SKADI_LOADER)
            return()
        endif()

        create_skadi_subsystem_custom_sources(EXT_NAME ${ext_name} APP ${app} SRCS ${ext_src})
    endfunction()


endif()


function(skadi_extension_add_sources extension)
    if(NOT CONFIG_SKADI_LOADER)
        return()
    endif()
    target_sources(${extension}_ext_llext_lib PRIVATE ${ARGN})
    target_sources(${extension}_ext_final_llext_lib PRIVATE ${ARGN})
endfunction(skadi_extension_add_sources)

function(skadi_extension_add_sources_ifdef extension CONFIG_SWITCH)
    if(NOT CONFIG_SKADI_LOADER)
        return()
    endif()
    if(${${CONFIG_SWITCH}})
        target_sources(${extension}_ext_llext_lib PRIVATE ${ARGN})
        target_sources(${extension}_ext_final_llext_lib PRIVATE ${ARGN})
    endif()
endfunction(skadi_extension_add_sources_ifdef)

function(skadi_extension_add_compile_options extension)
    if(NOT CONFIG_SKADI_LOADER)
        return()
    endif()
    target_compile_options(${extension}_ext_llext_lib PRIVATE ${ARGN})
    target_compile_options(${extension}_ext_final_llext_lib PRIVATE ${ARGN})
endfunction(skadi_extension_add_compile_options)

function(skadi_subsystem_add_libraries subsystem)
    target_link_libraries(${subsystem}_ext_llext_lib PRIVATE ${ARGN})
    target_link_libraries(${subsystem}_ext_final_llext_lib PRIVATE ${ARGN})
endfunction()

if(CONFIG_SKADI_INSECURE)
    message(WARNING "The currently selected Skadi configuration is INSECURE. Only use it in testing and DO NOT REPORT NUMBERS GENERATED USING THIS CONFIG in benchmarks!")
endif()

