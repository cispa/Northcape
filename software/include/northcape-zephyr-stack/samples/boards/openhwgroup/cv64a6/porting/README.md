# Skadi Porting

This sample serves as a starting point to understanding Skadi compartmentalization.
The sample contains two subsystems, `main` and `subsystem`.
`subsystem` exposes a subsystem call to the system.
`main` imports and invokes said subsystem call.

## Anatomy of a Subsystem
Creating a Skadi subsystem requires invoking one of the according CMake functions defined in `skadi.cmake`:
- `create_skadi_subsystem_eth_driver`, `create_skadi_subsystem_mdio_driver` and `create_skadi_subsystem_phy_driver` create subsystems specifically for Ethernet, MDIO and Ethernet PHY drivers. While the subsystems *themselves* are not special, these functions generate a *stub driver* for the networking subsystem. This is required for build-time discovery of network drivers to work and is *not needed* for other kinds of device drivers. A *naming convention* is used for back-and-forth calls between stub and real driver.
- `create_skadi_subsystem_main` is a convenience function for the subsystem that contains the *main* function.
- `create_skadi_subsystem_custom_sources` for anything else.

Sources of the subsystem can be provided to the functions that create it, or added later using the `skadi_extension_add_sources` and `skadi_extension_add_sources_ifdef` functions.
Likewise, compile and link options can be added immediately (`EXTRA_CPPFLAGS`, `EXTRA_LINK_FLAGS`) or later using `skadi_extension_add_compile_options` and `skadi_subsystem_add_libraries`.
The naming is inconsistent for historic reasons (subsystems were called extensions earlier in the project, as they are derived from LLEXT).

Several global options can also be added:
`FPU` indicates that the subsystem wants to use floating point operations.
A selection of other options is only used to break certain circular dependencies, e.g., in the allocator subsystem.

A subsystem normally consists of one or more C or assembly files that provide externally exposed subsystem calls.
Supporting libraries (e.g., the local allocator, the local clock subsystem, etc.) are appended automatically at build time, depending on system configuration.

The [CMakeLists.txt](CMakeLists.txt) file in this sample illustrates the creation of a main and a second, auxilliary, subsystem from [main.c](src/main.c) and [subsystem.c](src/subsystem.c), respectively.


## Initialization Functions
Skadi provides two different initialization functions:
- the `SYS_INIT` family of macros are compatible with Skadi. They work exactly the same as in zephyr. However, note that subsystems are only being initialized starting with the `PRE_KERNEL_1` init level.
- there is a macro `SKADI_SUBSYSTEM_INIT_FUNCTIONS`, which can be provided one or more function pointers that are to be called as soon as the subsystem has been relocated. Crucially, by the time these functions are called, memory permissions are still permissive. Thus, it is possible to, e.g., write otherwise read-only memory in such a function. Also, all `SKADI_SUBSYSTEM_INIT_FUNCTIONS` are called before the first `SYS_INIT` function is called. The signature of such an init function is: 
```C
static bool skadi_subsystem_init_function(void){
    return SUCCESS? true : false;
}
```

Examples for both init functions are provided in `main.c` and `subsystem.c`.
These functions are not always needed, but used transparently in, e.g., device drivers.

## Subsystem Calls
Subsystem calls transition between subsystems with *mutual isolation* of caller and callee.
To this end, special *caller and callee trampolines* save/restore or setup/teardown an execution context consisting of stack, registers etc.
These trampolines are auto-generated via special macros:
```C
#include <zephyr/skadi/skadi_subsystem.h>

/* from subsystem.h */
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE(int, __subsystem_call, int scalar, const struct dummy_subsystem_parameter *param);

/* adapted from subsystem.c */
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE(int, __subsystem_call, int scalar, const struct dummy_subsystem_parameter *param)
    return 0;
SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_END(__subsystem_call)
```

By convention, subsystem caller trampolines go into *C header files* for a certain subsystem, whereas subsystem callee trampolines go next to the function they are wrapping.
Also, subsystem call trampolines typically prepend two underscores to prevent naming conflicts.
Finally, caller trampolines are by convention *wrapped* with a macro or inline function.
This facilitates the generation of *derived capabilities* which can be shared between caller and callee safely (see [subsystem.h](src/subsystem.h) for an example).
To this end, Northcape capability operations are provided in `skadi_ops_driver.h`, which is transitively included by `skadi_subsystem.h`.
In particular, the header provides convenience functions `skadi_cap_ops_derive_arg` etc. that take an ordinary pointer and the size of the memory to be shared as inputs and return a suitable capability token.

Specialized versions of the subsystem call macros are provided for specific use cases:
- `SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_ALLOW_SELF` allows a subsystem call to be invoked from the same subsystem.
- `SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ` and `SKADI_SUBSYSTEM_CALLEE_TRAMPOLINE_NOIRQ_ALLOW_SELF` disable timer interrupts. These macros must be used for functions that can be called from interrupt handlers.
- `SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID` needs to be used for subsystem calls with return type *void*. The first parameter is the function name, not the return type, which is always *void*. This is needed for syntax reasons. No equivalent on the callee side needs to be used. Instead, the return type *void* may be used. On the callee side, a C11 `_Generic` statement is used to determine whether return argument registers need to be erased or not, and syntactically, there is no difference between void and non-void functions, so no separate macros are needed.
- `SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS`, `SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_VOID_ARGS` generate a caller trampoline that accepts a *function pointer* instead of matching a callee trampoline by name. The function pointer is to be omitted from the argument list of the macro, as it is always appended implicitly as the *last argument* of the generated trampoline.
- `SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_ARGS_VALIST` and variants generate a caller trampoline for a function that accepts a *va_list* argument (e.g., vprintf). See documentation for details.
- `*_ALLOW_SELF* variants of caller trampolines allow a caller to call itself. This is otherwise prevented.

Callee trampolines can be used as function pointer.
However, two special rules need to be considered:
- the function pointer is not callable directly. Instead, it needs to be passed to a trampoline generated by `SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_ARGS` or the appropriate variant of this macro.
- Taking the address of the callee trampoline by name does not provide a callable function pointer. Instead, to "convert" a callee trampoline to a function pointer, use the special macro `SKADI_SUBSYSTEM_FUNCTION_POINTER` and provide the name of the callee trampoline as argument.

Caller and callee trampolines for common system functions have been implemented:
For standard C library functions like `memset`, no special attention is needed - an appropriate implementation is available under that name.
However, for zephyr's public APIs, the appropriate header file needs to be included, and the naming scheme of the function has been changed.
You can look through *include/zephyr/skadi* to see which headers and functions are available.

Finally, it needs to be pointed out that currently, both caller and callee trampolines are limited to 8 arguments (7 for function pointer trampolines).
The reason for this is that RISC-V currently uses 8 argument registers, and deriving a capability for any remaining stack arguments is not implemented.
For the (very limited) functions that use >8 arguments, you can wrap the function arguments into a struct and derive a capability for it.

## Debugging Subsystems

In its default configuration, Skadi is configured for the highest possible security.
Thereby, debugging options are limited.
However, it can be configured to be more debugging-friendly at the cost of security:
- First, enable `CONFIG_SKADI_DEBUG`, which enables most debugging options by default.
- `CONFIG_SKADI_DEBUG_UNRESTRICTED_ROOT_CAP` can be set to disable task-ID restrictions for the root capability, useful to debug issues with MMIO devices.
- Skadi shares zephyr's `COMPILER_OPTIMIZATIONS` choice. Hence, selecting `CONFIG_DEBUG_OPTIMIZATIONS` instead of `CONFIG_SPEED_OPTIMIZATIONS` can help if there are issues with stepping through code or setting breakpoints due to inlining.

After configuring Skadi, load it with `west debug`.
You can set breakpoints immediately after the executable has finished loading.
However, using this method, you can only set breakpoints in the loader.
In order to set breakpoints in subsystems, wait for the subsystem of interest to be loaded and scan the output of the loader for lines like this:
```
I: Add subsystem symbols as follows in GDB (assuming "scripts/skadi/.gdbinit" was loaded):      
I: skadi_debug_subsystem loader_proxy 0x8ad6c040017e0000 0xaa218040017c0000 0xadd68040017a0000 0
xe35f404178000000
```
Copy the `skadi_debug_subsystem` command into the GDB shell and execute it.
After this, you can set breakpoints anywhere in the executable.

To conclude this section, here is a list of tidbits and gotchas:
- *Help, my subsystem crashes during initialization and I struggle to insert breakpoints!*. In this case, figure out when exactly the crash happens: Is it during the *subsystem loading process* or does it happen only after the last subsystem was loaded? In the first case, set a breakpoint into the `skadi_loader_init_functions` caller trampoline and single-step the CPU into your subsystem, trying to locate the crashing instruction. In the second case, set a breakpoint into `skadi_loader_print_memory_summary` - this is called immediately after the last subsystem was loaded, before the next init function is run.
- *I put a `printf` in an init function, but it is not printing anything!* Depending on the system state, printf calls take one of two possible routes: before the `POST_KERNEL` runlevel, printfs go through the *early console* which is implemented in the loader. Starting with `POST_KERNEL`, printfs go through the libc/uart_console/uart driver subsystems. Hence, first figure out where in the init sequence you are, and go from there. In particular, check for any conditions that can cause exceptions or other failures during printf processing (e.g., CMT exhaustion). You can use alternative means of debugging to check whether error conditions are true, e.g., you can use this code to insert breakpoints:
```C
__asm__ volatile("ebreak");
```
This will cause the CPU to stop execution when the code is executed and cause GDB to jump into console mode, and you can inspect register content and global/local data.
- *I want to view global data with GDB, but the content seems implausible*. In certain cases, GDB incorrectly relocates symbols. This seems to happen frequently with symbols in special sections, i.e., device structs. If this happens to you, verify carefully that the address that GDB thinks the symbol is at is within the bounds of the correct segment. You may also attempt to retrieve the real symbol address from local variables etc.
- *Skadi suddenly turned unresponsive, but there is no exception or other error message*. This can have multiple reasons: For one, you can encounter an exception early in the load process. Thus, the UART driver is not yet initialized, and the exception subsystem cannot print an error message (but the early console should prevent this). You could also have an exception that is so bad that the exception subsystem itself encounters an exception when it attempts to print the error message (e.g., CMT exhaustion). In that case, I suggest you add an `ebreak` instruction before the line `call skadi_handle_exception` in `exception_isr.S` under *subsys/skadi/exception*. You can then inspect register contents, the cause of the exception etc. in the GDB console like this: `p/x *(struct riscv_register_set *)$s0`. Finally, this could be a hardware issue (e.g., a hang of the resolver / L2 cache or a bug in the CPU pipeline). In this case, ask for help.


## Considerations for Interrupt Handlers

Due to Skadi's unique interrupt design, developing interrupt handlers comes with additional considerations that we detail below.

Conceptually, interrupt handlers in Skadi work the same as in zephyr: You register a callback function using `skadi_register_interrupt_handler` and enable the IRQ using `skadi_irq_enable`. Both functions are defined in `skadi_irq.h`, and you can follow the same configuration function convention that most zephyr drivers use to do this during device initialization.
This process is similar to the regular `IRQ_CONNECT` and `irq_enable` process used in zephyr.
Note that you need to provide an *interrupt priority* to enable an interrupt - use `SKADI_IRQ_PRIORITY_DEFAULT` if you are unsure.

Second, we provide a convenience wrapper that generates interrupt handler trampolines.
Use it like this:

```C
static void isr_handler(const struct device){
    // can be the exact same interrupt handler that you would use in zephyr - nothing special to do here!
}
// somewhere above the next line
#define DT_DRV_COMPAT my_company_my_device
	
SKADI_GENERATE_IRQ_HANDLER_WRAPPER(isr_handler);

// ...
// register the ISR handler like this in your init macro
skadi_register_interrupt_handler(DT_INST_IRQN(inst), NULL, SKADI_IRQ_HANDLER_FUNCTION_POINTER(inst,isr_handler));
```

Finally, as pointed out before, all functions that are called from an interrupt handler should use the `_NOIRQ` callee trampolines.
Also, (as in any other operating system) do not call functions that reschedule! 
However, Skadi operations, the allocator etc. can be used as normal.


## Considerations for Device Drivers

Skadi mostly uses zephyr's device model.
However, there are a few minor differences.

Device initialization and registration can use the same macros as it would in zephyr, including `DT_INST_REG_ADDR` (this will transparently request an MMIO capability token). Check out *skadi_ptp_clock_ha1588.c* for a simple example - read back from the `DT_INST_FOREACH_STATUS_OKAY` invocation and compare it to the regular *ptp_clock_ha1588.c* driver in zephyr.

There is an occasional quirk with MMIO tokens: Normally, the compiler knows the final physical address and its alignment.
Thus, it can safely generate word-size load and store instructions.
However, in Skadi, the final MMIO address is only known at run time.
On some occasions, the compiler makes the assumption that the MMIO token is *not* guaranteed to be word-aligned (as it does not know that it actually is) and generates *byte* load and store operations. Certain Xilinx IP cores cannot handle byte-size loads and stores properly, causing incorrect behavior. As a general fix, we force the appropriate read and write sizes in the `sys_read8/16/32/64` and `sys_write8/16/32/64` functions. Thus, all MMIO accesses should use these functions!


Device APIs however need to use *set-task-id capabilities* instead of regular function pointers.
Unfortunately, at this time, we have no transparent mechanism to insert them.
Thus, you have to provide these tokens yourself and wrap all device API functions in subsystem callee trampolines.
On the same note, zephyr usually provides wrapper functions to invoke the device API (for example, `uart_line_ctrl_get`).
In the same way as for any other subsystem call, you have to create wrappers and function pointer trampolines for these API functions. As an example, see `skadi_uart_line_ctrl_get` in `skadi_uart.h`.
Adding insult to injury, the device API is normally constant and cannot be changed from the regular device initialization routine.
As a workaround, Skadi drivers register `SKADI_SUBSYSTEM_INIT_FUNCTIONS` (see above) that manipulate the API struct.
Again, see how the `ptp_clock_ha1588_api` is constructed in both versions of the ha1588 driver.

A final quirk concerns addressing devices and their internals (config and data).
By default, subsystems export devices, and the loader derives appropriate read-only capabilities for the device.
Thereby, other subsystems can import the device, query basic public information and access its API.
However, when invoking an API, the caller could theoretically provide an *arbitrary* capability for the device, causing unintended and possibly exploitable behavior in the driver.
Hence, the driver needs to be sure it is working on the correct device.
Thus, a special wrapper function `skadi_get_own_device_representation` is invoked on every device passed as a parameter.
Again, see *skadi_ptp_clock_ha1588.c* for an example. The function can mostly be generated using `SKADI_GET_OWN_DEVICE_REPRESENTATION`, which depends on `DT_DRV_COMPAT`. The wrapper iterates all device instances known to the driver and identifies the provided device based on its device ID, returning the local device to any API function.
