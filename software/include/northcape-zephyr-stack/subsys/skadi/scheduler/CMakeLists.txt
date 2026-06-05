if(CONFIG_SKADI_OS)
    # "kernel" does not exist at run time
    # so we have to duplicate a few kernel sources...
    create_skadi_subsystem_custom_sources(
        EXT_NAME scheduler
        APP zephyr
        SRCS 
            scheduler_subsystem.c
            # wrappers for normal sys-clock functions
            sys_clock_stub.c
            riscv_thread_start.S
            ${ZEPHYR_BASE}/subsys/skadi/isr/skadi_switch.S
            ${ZEPHYR_BASE}/kernel/idle.c
            # init behaves differently in the kernel vs. outside of the kernel
            ${ZEPHYR_BASE}/kernel/init.c
            ${ZEPHYR_BASE}/kernel/mailbox.c
            ${ZEPHYR_BASE}/kernel/msg_q.c
            ${ZEPHYR_BASE}/kernel/mutex.c
            ${ZEPHYR_BASE}/kernel/queue.c
            ${ZEPHYR_BASE}/kernel/sem.c
            ${ZEPHYR_BASE}/kernel/stack.c
            ${ZEPHYR_BASE}/kernel/system_work_q.c
            ${ZEPHYR_BASE}/kernel/work.c
            ${ZEPHYR_BASE}/kernel/condvar.c
            ${ZEPHYR_BASE}/kernel/priority_queues.c
            ${ZEPHYR_BASE}/kernel/thread.c
            ${ZEPHYR_BASE}/kernel/sched.c
            ${ZEPHYR_BASE}/kernel/init_static.c
            ${ZEPHYR_BASE}/kernel/banner.c
            ${ZEPHYR_BASE}/lib/os/thread_entry.c
            # scheduler-related kernel files
            ${ZEPHYR_BASE}/kernel/kheap.c
            ${ZEPHYR_BASE}/kernel/mem_slab.c
            ${ZEPHYR_BASE}/kernel/mempool.c
            ${ZEPHYR_BASE}/lib/heap/heap.c
            # architecture-specific kernel files
            ${ZEPHYR_BASE}/arch/riscv/core/cpu_idle.c
            ${ZEPHYR_BASE}/arch/riscv/core/thread.c
            # TODO tracing
            ${ZEPHYR_BASE}/subsys/tracing/tracing_none.c
        EXTRA_CPPFLAGS
            -I${ZEPHYR_BASE}/arch/riscv/include
            -I${ZEPHYR_BASE}/arch/riscv/core
            -I${ZEPHYR_BASE}/kernel/include
            -DSCHEDULER_SUBSYSTEM
        )
        

    skadi_extension_add_sources_ifdef(scheduler CONFIG_POLL             ${ZEPHYR_BASE}/kernel/poll.c)
    skadi_extension_add_sources_ifdef(scheduler CONFIG_EVENTS           ${ZEPHYR_BASE}/kernel/events.c)
    skadi_extension_add_sources_ifdef(scheduler CONFIG_PIPES            ${ZEPHYR_BASE}/kernel/pipes.c)
    skadi_extension_add_sources_ifdef(scheduler CONFIG_TIMESLICING      ${ZEPHYR_BASE}/kernel/timeslicing.c)
    skadi_extension_add_sources_ifdef(scheduler CONFIG_THREAD_MONITOR   ${ZEPHYR_BASE}/kernel/thread_monitor.c)
    # TODO separate subsystem
    skadi_extension_add_sources_ifdef(scheduler CONFIG_SYS_CLOCK_EXISTS ${ZEPHYR_BASE}/kernel/timeout.c ${ZEPHYR_BASE}/kernel/timer.c)
endif()
