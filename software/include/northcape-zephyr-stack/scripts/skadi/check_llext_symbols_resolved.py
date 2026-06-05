#!/usr/bin/python3
import argparse
import logging
import subprocess
from pathlib import Path
from sys import exit, argv
import os
import json
import re

if 'VERBOSE' in os.environ:
    logging.basicConfig(level = logging.DEBUG)
else:
    logging.basicConfig(level = logging.INFO)


def parse_args()->tuple[bool,str,Path,Path,Path]:
    parser = argparse.ArgumentParser(description="Check whether llexts in given directory use unresolveable (i.e., unexported) symbols.")
    parser.add_argument('--llext-dir', type=Path, required='--check-symbols' in argv, default=None, help='Directory where .llext binaries reside')
    parser.add_argument('--zephyr-binary', type=Path, required='--check-symbols' in argv, default=None, help='Path to zephyr binary')
    parser.add_argument('--trampolines-out', type=Path, required='--generate-caller-trampolines' in argv, default=None, help='Path to generated trampoline file')
    parser.add_argument('--generate-caller-trampolines', type=str, required=False, default=False, help='Generate skadi subsystem caller trampoline source file for given files')
    parser.add_argument('--check-symbols', action='store', nargs='*', help="Check resolved symbols")

    args = parser.parse_args()



    logging.debug(f"Got zephyr binary {args.zephyr_binary} llext dir {args.llext_dir}")

    return args.check_symbols is not None, args.generate_caller_trampolines, args.trampolines_out, args.zephyr_binary, args.llext_dir

def get_llext_binaries(llext_dir:Path)->list[str]:
    ret = []

    for file in llext_dir.iterdir():
        if(file.is_file()):
            if(file.suffix ==".llext"):
                file_path = str(file.absolute())
                ret.append(file_path)
                logging.debug(f"Found llext debug file {file_path}")

    return ret

def invoke_pipe(command: str) -> set[str]:
    process = subprocess.run(["sh", "-c", command], capture_output=True, text=True)
    stdout = process.stdout
    stderr = process.stderr

    

    if(len(stderr) > 0):
        logging.warning(f"Standard error for getting exported symbols: {stderr}")
    
    return stdout.split("\n")

def get_exported_symbols(elf:str) -> str:
    command = f"readelf -W --syms {elf} | grep '_sym$' | awk '{{print $8;}}'"
    return invoke_pipe(command)

def get_imported_symbols(elf:str) -> str:
    command = f"readelf -W --syms {elf} | grep 'UND' | grep -v 'LOCAL' | awk '{{print $8;}}'"
    return invoke_pipe(command)

mmio_regex = re.compile("^__skadi_mmio_\d+_(\d+)_(\d+)$")

caller_trampo_regex = re.compile("^__skadi_[a-zA-Z_]+_caller_trampolines$")
caller_trampo_regex_irq = re.compile("^__skadi_[a-zA-Z_]+_caller_trampolines_irq$")

def filter_mmio(symbol):
    return not mmio_regex.match(symbol) and not caller_trampo_regex.match(symbol)  and not caller_trampo_regex_irq.match(symbol) and symbol != "skadi_subsystem_mtimer_sched_hook" and symbol != "__skadi_subsystem_mtime_reg_capability" and symbol != "__skadi_boot_time"

def remove_well_known_imported_symbols(llext_path: str, imported_symbols: set[str])->set[str]:    
    if(llext_path.endswith("/allocator.llext")):
        if "__skadi_allocator_arena_start" in imported_symbols:
            imported_symbols.remove("__skadi_allocator_arena_start")
        if "__skadi_allocator_arena" in imported_symbols:
            imported_symbols.remove("__skadi_allocator_arena")
        if "__skadi_allocator_arena_size_bytes" in imported_symbols:
            imported_symbols.remove("__skadi_allocator_arena_size_bytes")
    return set(filter(filter_mmio, imported_symbols))

def check_llext_entry( llext_path: str, imported_symbols: set[str], exported_symbols: set[str]) -> bool:
    imported_symbols = remove_well_known_imported_symbols(llext_path, imported_symbols) # this gets rid of false positives, which are filled in by the loader
    unresolved_syms = imported_symbols - exported_symbols

    logging.debug(f"LLEXT {llext_path} imports resolved symbols {json.dumps(list(imported_symbols), indent=2)}")

    if(len(unresolved_syms)):
        logging.error(f"LLEXT {llext_path} has unresolved symbols {json.dumps(list(unresolved_syms), indent=2)}")
        return False
    else:
        return True

# https://stackoverflow.com/a/73413013
def replace_last(string, old, new):
    old_idx = string.rfind(old)
    return string[:old_idx] + new + string[old_idx+len(old):]

trampoline_regex = re.compile("__skadi_caller_trampoline(_fn_ptr)?(_va)?((_void_)|(_retval_))(allow_self_)?_(\d+)__([a-zA-Z0-9_]+)")
trampoline_regex_group_is_fn_ptr = 1
trampoline_regex_group_is_va = 2
trampoline_regex_group_is_void = 3
trampoline_regex_group_allow_self = 6
trampoline_regex_group_num_args = 7
trampoline_regex_group_name = 8

def is_caller_trampoline(symbol: str)->bool:
    return trampoline_regex.match(symbol)

def generate_trampoline(symbol: str)->bool:
    re_match = trampoline_regex.match(symbol)

    symbol_is_va = re_match.group(trampoline_regex_group_is_va) == '_va'

    num_args = int(re_match.group(trampoline_regex_group_num_args))

    is_void = re_match.group(trampoline_regex_group_is_void) == '_void_'
    
    is_fn_ptr = re_match.group(trampoline_regex_group_is_fn_ptr) == '_fn_ptr'

    allow_self = re_match.group(trampoline_regex_group_allow_self) == 'allow_self_'
    
    trampoline_name = re_match.group(trampoline_regex_group_name)
    callee_side_name = trampoline_name

    arg_str = ""

    retval_arg = "uintptr_t"

    # trampoline itself uses the allocator for setup
    # so we need to make sure that this trampoline has the correct signature
    if trampoline_name == '__skadi_allocator_alloc':
        arg_str = ', uint32_t requested_size, uint32_t align, skadi_permission_type_t permissions'
        retval_arg = "void *"
    elif trampoline_name == '__skadi_allocator_free':
        arg_str = ', void *token'
        retval_arg = "bool"
    elif trampoline_name == '__skadi_allocator_allocated_chunks':
        arg_str = ''
        retval_arg = "atomic_val_t"
    elif trampoline_name == 'riscv_plic_irq_enable':
        arg_str = ', uint32_t irq'
        retval_arg = 'void'
    elif trampoline_name == 'riscv_plic_irq_disable':
        arg_str = ', uint32_t irq'
        retval_arg = 'void'
    elif trampoline_name == 'riscv_plic_irq_is_enabled':
        arg_str = ', uint32_t irq'
        retval_arg = 'int'
    elif trampoline_name == 'riscv_plic_set_priority':
        arg_str = ', uint32_t irq, uint32_t priority'
        retval_arg = 'void'
    elif trampoline_name == 'skadi_plic_register_handler':
        arg_str = ', const int irq_number, const void *ag, void (*isr)(const void *arg)'
        retval_arg = 'bool'
    elif trampoline_name == 'skadi_isr_register_handler':
        arg_str = ', const int irq_number, const void *ag, void (*isr)(const void *arg)'
        retval_arg = 'bool'
    else:
        for i in range(0, num_args):
            arg_str = arg_str + ", "
            # register-wide argument should cover it
            arg_str = arg_str + f"uintptr_t arg_{i}"
    va_prefix=""
    # the extra argument is not accounted for in the name
    if(symbol_is_va):
        num_args = num_args + 1
        # convention
        callee_side_name = "__" + trampoline_name
        va_prefix="va_"
    allow_self_suffix = '_ALLOW_SELF' if allow_self else ''

    if is_fn_ptr:
        if is_void:
            # function pointer void
            # valist accounted for with number of arguments

            return f"""
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_{va_prefix.upper()}VOID_IMPL{allow_self_suffix}({trampoline_name}, {num_args}{arg_str});
"""
        else:
            # function pointer with return value
            # assume return type uintptr_t (full reg)
            return f"""
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_FN_PTR_{va_prefix.upper()}IMPL{allow_self_suffix}({retval_arg}, {trampoline_name}, {num_args}{arg_str});
"""
    else:
        if is_void:
            # by-name void
            return f"""
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID_IMPL{allow_self_suffix}({trampoline_name}, {callee_side_name}, {va_prefix}, {num_args}{arg_str});
"""
        else:
            # retval void
            # assume return type uintptr_t (full reg)
            return f"""
SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_IMPL{allow_self_suffix}({retval_arg}, {trampoline_name}, {callee_side_name}, {va_prefix}, {num_args}{arg_str});
"""

def main():
    do_check, trampoline_sources_in, trampolines_out, zephyr_binary, llext_dir = parse_args()
    if do_check:
        llext_binaries = get_llext_binaries(llext_dir)
    else:
        # TODO get object files
        llext_binaries = [Path(individual_path) for individual_path in trampoline_sources_in.split(";")]
        # we have to filter out the trampoline which we are about to create
        llext_binaries = list(filter(lambda path: not path.stem.endswith("_caller_trampolines.c"), llext_binaries))
        
        for binary in llext_binaries:
            if not binary.is_file():
                logging.error(f"File {binary.absolute()} does not exist!")
                exit(1)
        llext_binaries = [str(individual_path.absolute()) for individual_path in llext_binaries]
        logging.debug(f"Resolved llext object files {llext_binaries}")

    imported_dict = { llext_path : set(get_imported_symbols(llext_path)) for llext_path in llext_binaries}

    if do_check:
        # zephyr.elf by definition does not import symbols
        llext_binaries = llext_binaries + [str(zephyr_binary.absolute())]

    exported_list = []
    [exported_list.extend([(item, llext_path) for item in get_exported_symbols(llext_path)]) for llext_path in llext_binaries]
    
    exported_set = set()
    for item, path in exported_list:
        if item == '' or item == '.exported_sym':
            # special, unused names
            continue
        if item.endswith("_sym"):
            # appended by llext naming scheme...
            exported_set.add(replace_last(item, "_sym", ""))
            logging.debug(f"LLEXT {path} exports {item}!")
        else:
            logging.warning(f"Ignored export {item} as it does not end in _sym!")
    
    # special / dummy imports
    exported_set.add('')
    exported_set.add('tohost')

    if do_check:
        retval = True
        for llext_path, imported_symbols in imported_dict.items():
            logging.debug(f"Checking llext {llext_path}")
            if not check_llext_entry(llext_path, imported_symbols, exported_set):
                retval = False
    else:
        retval = True
        trampoline = '''
#include <zephyr/skadi/skadi_subsystem.h>
'''
        caller_trampolines = set()

        for llext_path, imported_symbols in imported_dict.items():
            for symbol in imported_symbols:
                if is_caller_trampoline(symbol):
                    caller_trampolines.add(symbol)
        logging.debug(f"Have to generate trampolines for symbols {caller_trampolines} from imported dict {imported_dict.items()}")

        for symbol in caller_trampolines:
            trampoline = trampoline + generate_trampoline(symbol)

        with open(trampolines_out, 'w') as file:
            file.write(trampoline)
    
    exit(0 if retval else 1)


if __name__ == "__main__":
    main()
