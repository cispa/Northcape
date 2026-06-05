# usage: skadi_debug_subsystem <llext_name> <text address> <data address> <rodata address> <bss address>
define skadi_debug_subsystem
	shell ./zephyr-sdk-custom/riscv64-zephyr-elf/bin/riscv64-zephyr-elf-objcopy --change-section-address .text=$arg1 --change-section-address .data=$arg2 --change-section-address .rodata=$arg3 --change-section-address .bss=$arg4 build/zephyr/$arg0.llext build/zephyr/$arg0.llext.relocated
	add-symbol-file build/zephyr/$arg0.llext.relocated
end

