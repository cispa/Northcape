# Skadi Compartmentalized RTOS aka Skadi

## Skadi Loader Conventions

Compartmentalized tasks can define the following symbols, which are interpreted by the Skadi Loader:

- Functions in a special ELF section `.init_array` are called at the beginning of task execution.
- Likewise, `.fini_array` defines teardown functions.
- Functions can be explicitly exported by adding a reference to them in the `llext_exports_strtab` section.
    - For each exported function `foobar`, the loader expects three symbols: `foobar_callee_trampoline`, `foobar_callee_trampoline_end`, `foobar_callee_trampoline_function_pointer`.
    - `foobar_callee_trampoline` and `foobar_callee_trampoline_end` are required for exporting the function, they mark the beginning and end of the callee trampoline. 
    - The loader derives a set-task-id capability for `foobar`, which other tasks can use to invoke subsystem calls into `foobar`.
    - The optional symbol `foobar_callee_trampoline_function_pointer` is written by the loader. By the time the first initialization function is run, it is guaranteed to contain the set-task-id capability for `foobar`.
- Functions can be imported by leaving them undefined. This will import the corresponding set-task-id tokens required to perform subsystem calls into the functions.
- Tasks can define a symbol `<taskname>_context_switch_hook`. This is required to be a `uintptr_t`. The loader will overwrite this symbol with a capability to the capability `mtimer` ISR. The task needs to overwrite this capability with a function pointer to its own mtimer handler each time it gains control of the CPU (e.g., in its subsystem callee trampoline). The mtimer handler is expected to make a subsystem call into the scheduler, saving all registers of the task to prevent them from being leaked.
- Task can define a symbol `taskname_iomem_<addr in hex>_<length in hex>.` The loader will check if the task is allowed to access the I/O memory at the given address, and if so, load a read/write capability for the corresponding range of I/O memory that the task can use for direct access to devices.
