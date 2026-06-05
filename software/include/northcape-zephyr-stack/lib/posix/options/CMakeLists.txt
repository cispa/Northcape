# SPDX-License-Identifier: Apache-2.0

set(GEN_DIR ${ZEPHYR_BINARY_DIR}/include/generated)

if(CONFIG_SKADI_OS)

  # files deliberately NOT ported:
  # - fd_mgmt - variadic functions; will implement with appropriate caller trampoline
  if(CONFIG_POSIX_API OR CONFIG_POSIX_THREADS OR CONFIG_POSIX_TIMERS OR
    CONFIG_POSIX_MESSAGE_PASSING OR CONFIG_POSIX_FILE_SYSTEM OR CONFIG_EVENTFD OR
    CONFIG_POSIX_C_LIB_EXT OR CONFIG_POSIX_SINGLE_PROCESS)
    create_skadi_subsystem_custom_sources(EXT_NAME posix APP zephyr SRCS EXTRA_CPPFLAGS -I${ZEPHYR_BASE}/kernel/include -I${ARCH_DIR}/${ARCH}/include -I${ZEPHYR_BASE}/include/zephyr/posix -I${CMAKE_CURRENT_SOURCE_DIR}/getopt -include ${ZEPHYR_BASE}/include/zephyr/skadi/skadi_errno.h)
  endif()

  zephyr_syscall_header_ifdef(CONFIG_POSIX_TIMERS posix_clock.h)

  if (NOT CONFIG_TC_PROVIDES_POSIX_SIGNALS)
    if(CONFIG_POSIX_SIGNALS)
      set(STRSIGNAL_TABLE_H ${GEN_DIR}/posix/strsignal_table.h)

      add_custom_command(
        OUTPUT ${STRSIGNAL_TABLE_H}
        COMMAND
        ${PYTHON_EXECUTABLE}
        ${ZEPHYR_BASE}/scripts/build/gen_strsignal_table.py
        -i ${ZEPHYR_BASE}/include/zephyr/posix/signal.h
        -o ${STRSIGNAL_TABLE_H}
        DEPENDS ${ZEPHYR_BASE}/include/zephyr/posix/signal.h
      )
    endif()
  endif()

  if(CONFIG_POSIX_API OR CONFIG_POSIX_THREADS OR CONFIG_POSIX_TIMERS OR
    CONFIG_POSIX_MESSAGE_PASSING OR CONFIG_POSIX_FILE_SYSTEM OR CONFIG_EVENTFD OR
    CONFIG_POSIX_C_LIB_EXT OR CONFIG_POSIX_SINGLE_PROCESS)
    # This is a temporary workaround so that Newlib declares the appropriate
    # types for us. POSIX features to be formalized as part of #51211
    zephyr_compile_options($<$<COMPILE_LANGUAGE:C>:-D_POSIX_THREADS>)
    zephyr_compile_options($<$<COMPILE_LANGUAGE:CXX>:-D_POSIX_THREADS>)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_ASYNCHRONOUS_IO)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_ASYNCHRONOUS_IO aio.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_BARRIERS)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_BARRIERS barrier.c)
  endif()

  skadi_extension_add_sources_ifdef(posix CONFIG_EVENTFD skadi_eventfd.c)

  if (NOT CONFIG_TC_PROVIDES_POSIX_C_LIB_EXT)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_C_LIB_EXT
      fnmatch.c
      skadi_getentropy.c
      getopt/getopt.c
      getopt/getopt_common.c
    )
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_DEVICE_IO)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_DEVICE_IO
      # perror should be moved to the common libc
      perror.c
      skadi_device_io.c
    )
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_FILE_SYSTEM)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_FILE_SYSTEM fs.c)
  endif()

  skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_FSYNC fsync.c)
  skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_MEMLOCK mlockall.c)
  skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_MEMLOCK_RANGE mlock.c)

  if (NOT CONFIG_TC_PROVIDES_POSIX_MEMORY_PROTECTION)
  skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_MEMORY_PROTECTION mprotect.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_MAPPED_FILES)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_MAPPED_FILES mmap.c)
  endif()

  skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_MESSAGE_PASSING skadi_mqueue.c)

  if (NOT CONFIG_TC_PROVIDES_POSIX_MULTI_PROCESS)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_MULTI_PROCESS
      sleep.c
      multi_process.c
    )
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_NETWORKING)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_NETWORKING skadi_net.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SHARED_MEMORY_OBJECTS)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_SHARED_MEMORY_OBJECTS shm.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SIGNALS)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_SIGNALS signal.c ${STRSIGNAL_TABLE_H})
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SINGLE_PROCESS)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_SINGLE_PROCESS
      confstr.c
      env.c
      sysconf.c
      uname.c
    )
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SPIN_LOCKS)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_SPIN_LOCKS spinlock.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_TIMERS)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_TIMERS
      clock.c
      timer.c
      timespec_to_timeout.c
    )
  endif()

  skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_PRIORITY_SCHEDULING sched.c)

  if (NOT CONFIG_TC_PROVIDES_POSIX_READER_WRITER_LOCKS)
    # Note: the Option is _POSIX_READER_WRITER_LOCKS, while the Option Group is POSIX_RW_LOCKS.
    # We have opted to use POSIX_READER_WRITER_LOCKS here to match the Option name.
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_READER_WRITER_LOCKS rwlock.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SEMAPHORES)
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_SEMAPHORES semaphore.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_THREADS)
    # Note: the Option is _POSIX_THREADS, while the Option Group is POSIX_THREADS_BASE.
    # We have opted to use POSIX_THREADS here to match the Option name.
    skadi_extension_add_sources_ifdef(posix CONFIG_POSIX_THREADS
      cond.c
      grp.c
      key.c
      mutex.c
      pthread.c
      pwd.c
    )
  endif()

  skadi_extension_add_sources_ifdef(posix CONFIG_XOPEN_STREAMS stropts.c)

  if (NOT CONFIG_TC_PROVIDES_XSI_SYSTEM_LOGGING)
    skadi_extension_add_sources_ifdef(posix CONFIG_XSI_SYSTEM_LOGGING syslog.c)
  endif()

  skadi_extension_add_sources_ifdef(posix CONFIG_GETOPT_LONG
    getopt/getopt_long.c
  )
  zephyr_include_directories_ifdef(CONFIG_POSIX_C_LIB_EXT
    getopt/
  )

else()

  zephyr_syscall_header_ifdef(CONFIG_POSIX_TIMERS posix_clock.h)

  if(CONFIG_POSIX_API)
    zephyr_include_directories(${ZEPHYR_BASE}/include/zephyr/posix)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SIGNALS)
    if(CONFIG_POSIX_SIGNALS)
      set(STRSIGNAL_TABLE_H ${GEN_DIR}/posix/strsignal_table.h)

      add_custom_command(
        OUTPUT ${STRSIGNAL_TABLE_H}
        COMMAND
        ${PYTHON_EXECUTABLE}
        ${ZEPHYR_BASE}/scripts/build/gen_strsignal_table.py
        -i ${ZEPHYR_BASE}/include/zephyr/posix/signal.h
        -o ${STRSIGNAL_TABLE_H}
        DEPENDS ${ZEPHYR_BASE}/include/zephyr/posix/signal.h
      )
    endif()
  endif()

  if(CONFIG_POSIX_API OR CONFIG_POSIX_THREADS OR CONFIG_POSIX_TIMERS OR
    CONFIG_POSIX_MESSAGE_PASSING OR CONFIG_POSIX_FILE_SYSTEM OR CONFIG_EVENTFD OR
    CONFIG_POSIX_C_LIB_EXT OR CONFIG_POSIX_SINGLE_PROCESS)
    # This is a temporary workaround so that Newlib declares the appropriate
    # types for us. POSIX features to be formalized as part of #51211
    zephyr_compile_options($<$<COMPILE_LANGUAGE:C>:-D_POSIX_THREADS>)
    zephyr_compile_options($<$<COMPILE_LANGUAGE:CXX>:-D_POSIX_THREADS>)
  endif()

  zephyr_library()
  zephyr_library_sources_ifdef(CONFIG_EVENTFD eventfd.c)

  if (NOT CONFIG_TC_PROVIDES_POSIX_ASYNCHRONOUS_IO)
    zephyr_library_sources_ifdef(CONFIG_POSIX_ASYNCHRONOUS_IO aio.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_BARRIERS)
    zephyr_library_sources_ifdef(CONFIG_POSIX_BARRIERS barrier.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_C_LIB_EXT)
    zephyr_library_sources_ifdef(CONFIG_POSIX_C_LIB_EXT
      fnmatch.c
      getentropy.c
      getopt/getopt.c
      getopt/getopt_common.c
    )
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_DEVICE_IO)
    zephyr_library_sources_ifdef(CONFIG_POSIX_DEVICE_IO
      # perror should be moved to the common libc
      perror.c
      device_io.c
    )
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_FILE_SYSTEM)
    zephyr_library_sources_ifdef(CONFIG_POSIX_FILE_SYSTEM fs.c)
  endif()

  zephyr_library_sources_ifdef(CONFIG_POSIX_FSYNC fsync.c)
  zephyr_library_sources_ifdef(CONFIG_POSIX_MEMLOCK mlockall.c)
  zephyr_library_sources_ifdef(CONFIG_POSIX_MEMLOCK_RANGE mlock.c)

  if (NOT CONFIG_TC_PROVIDES_POSIX_MEMORY_PROTECTION)
  zephyr_library_sources_ifdef(CONFIG_POSIX_MEMORY_PROTECTION mprotect.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_MAPPED_FILES)
    zephyr_library_sources_ifdef(CONFIG_POSIX_MAPPED_FILES mmap.c)
  endif()

  zephyr_library_sources_ifdef(CONFIG_POSIX_MESSAGE_PASSING mqueue.c)

  if (NOT CONFIG_TC_PROVIDES_POSIX_MULTI_PROCESS)
    zephyr_library_sources_ifdef(CONFIG_POSIX_MULTI_PROCESS
      sleep.c
      multi_process.c
    )
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_NETWORKING)
    zephyr_library_sources_ifdef(CONFIG_POSIX_NETWORKING net.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SHARED_MEMORY_OBJECTS)
    zephyr_library_sources_ifdef(CONFIG_POSIX_SHARED_MEMORY_OBJECTS shm.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SIGNALS)
    zephyr_library_sources_ifdef(CONFIG_POSIX_SIGNALS signal.c ${STRSIGNAL_TABLE_H})
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SINGLE_PROCESS)
    zephyr_library_sources_ifdef(CONFIG_POSIX_SINGLE_PROCESS
      confstr.c
      env.c
      sysconf.c
      uname.c
    )
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SPIN_LOCKS)
    zephyr_library_sources_ifdef(CONFIG_POSIX_SPIN_LOCKS spinlock.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_TIMERS)
    zephyr_library_sources_ifdef(CONFIG_POSIX_TIMERS
      clock.c
      timer.c
      timespec_to_timeout.c
    )
  endif()

  zephyr_library_sources_ifdef(CONFIG_POSIX_PRIORITY_SCHEDULING sched.c)

  if (NOT CONFIG_TC_PROVIDES_POSIX_READER_WRITER_LOCKS)
    # Note: the Option is _POSIX_READER_WRITER_LOCKS, while the Option Group is POSIX_RW_LOCKS.
    # We have opted to use POSIX_READER_WRITER_LOCKS here to match the Option name.
    zephyr_library_sources_ifdef(CONFIG_POSIX_READER_WRITER_LOCKS rwlock.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_SEMAPHORES)
    zephyr_library_sources_ifdef(CONFIG_POSIX_SEMAPHORES semaphore.c)
  endif()

  if (NOT CONFIG_TC_PROVIDES_POSIX_THREADS)
    # Note: the Option is _POSIX_THREADS, while the Option Group is POSIX_THREADS_BASE.
    # We have opted to use POSIX_THREADS here to match the Option name.
    zephyr_library_sources_ifdef(CONFIG_POSIX_THREADS
      cond.c
      grp.c
      key.c
      mutex.c
      pthread.c
      pwd.c
    )
  endif()

  zephyr_library_sources_ifdef(CONFIG_XOPEN_STREAMS stropts.c)

  if (NOT CONFIG_TC_PROVIDES_XSI_SYSTEM_LOGGING)
    zephyr_library_sources_ifdef(CONFIG_XSI_SYSTEM_LOGGING syslog.c)
  endif()

  zephyr_library_sources_ifdef(CONFIG_GETOPT_LONG
    getopt/getopt_long.c
  )
  zephyr_include_directories_ifdef(CONFIG_POSIX_C_LIB_EXT
    getopt/
  )

  zephyr_library_include_directories(
    ${ZEPHYR_BASE}/kernel/include
    ${ARCH_DIR}/${ARCH}/include
  )

  zephyr_library_property(ALLOW_EMPTY TRUE)

endif()
