#!/usr/bin/python3
import argparse
import logging
import os
from os import listdir
from os.path import isfile, join
import lief
from graphlib import TopologicalSorter 
import re
import glob
import shutil

if 'VERBOSE' in os.environ:
    logging.basicConfig(level = logging.DEBUG)
else:
    logging.basicConfig(level = logging.INFO)



def parse_args()->tuple[str,str,str]:
    parser = argparse.ArgumentParser(description="Generate a C header that initializes Skadi subsystems in the correct order.")
    parser.add_argument('--header_out', type=str, required=True, help='Output path')
    parser.add_argument('--sd_dir_out', type=str, required=True, help='Output path for SD card directory')
    parser.add_argument('--llext-dir', type=str, required=True, help='Directory where .llext binaries reside')

    args = parser.parse_args()



    logging.debug(f"Got outfile {args.header_out} SD out dir {args.sd_dir_out} llext output dir {args.llext_dir}")

    return args.header_out, args.sd_dir_out, args.llext_dir


def get_llext_binaries(llext_dir:str)->list[str]:
    ret = []

    for file in listdir(llext_dir):
        if(isfile(join(llext_dir,file))):
            if(file.endswith(".llext")):
                ret.append(join(llext_dir,file))
                logging.debug(f"Found llext subsystem {file}")

    return ret

SHN_UNDEF=0

def get_elf_imported_exported_data(parsed_input:lief.Binary)->tuple[list[str],list[str]]:
    imported_data = []
    exported_data = []
    considered_data_name_prefixes = ["__device_dts_ord"]


    for symbol in parsed_input.symbols:
        matches_any_prefix = False
        # imported symbols have notype
        if(symbol.type != lief.ELF.Symbol.TYPE.OBJECT and symbol.type != lief.ELF.Symbol.TYPE.NOTYPE):
            continue
        if(symbol.binding != lief.ELF.Symbol.BINDING.GLOBAL):
            continue
        if(symbol.exported):
            exported_data.append(symbol.name)
        else:
            imported_data.append(symbol.name)
    return imported_data,exported_data
        
def get_elf_imports_exports(llext:str)->tuple[list[str],list[str]]:
    parsed_input = lief.parse(llext)
    
    imported_functions = [function.name for function in parsed_input.imported_functions]
    exported_functions = [function.name for function in parsed_input.exported_functions]

    imported_data, exported_data = get_elf_imported_exported_data(parsed_input)

    logging.debug(f"Subsystem {llext} imports functions {imported_functions} exports functions {exported_functions} imports data {imported_data} exports data {exported_data}")
    return imported_functions + imported_data, exported_functions + exported_data

def sort(llext_binaries:list[str])->list[str]:
    exported_dict = {}
    dependency_dict = {}
    num_exported = 0
    num_imported = 0
    actually_imported_set = set()
    
    for binary in llext_binaries:
        _, exported_functions = get_elf_imports_exports(binary)
        exported_dict[binary]=exported_functions
        exported_functions =[fn for fn in exported_functions if fn.endswith("_callee_trampoline")]
        num_exported += len(exported_functions)
    
    logging.debug(f"Exported dict: {exported_dict}")

    for binary in llext_binaries:
        imported_functions, _ = get_elf_imports_exports(binary)
        
        dependent_subsystems = []
        for subsystem, exports in exported_dict.items():
            logging.debug(f"Comparing imports {imported_functions} into subsystem {binary} with exports {exports} from subsystem {subsystem}!")
            intersection = list(set(imported_functions) & set(exports))
            actually_imported_set = actually_imported_set | (set(imported_functions) & set(exports))
            if(len(intersection) > 0):
                logging.debug(f"Subsystem {binary} imports functions {intersection} from subsystem {subsystem}!")
                dependent_subsystems.append(subsystem)
        dependency_dict[binary] = dependent_subsystems
    
    num_imported = len(actually_imported_set)

    sorter = TopologicalSorter()

    pattern = re.compile('^(\/.*\/)+(\w+)\.llext$', re.IGNORECASE)

    for subsystem, dependencies in dependency_dict.items():
        logging.debug(f"Pattern {pattern} on subsystem {subsystem}")
        # entries are full path names at this point, cut out the paths with regex
        subsystem = pattern.match(subsystem).group(2)
        dependencies = [pattern.match(dependency).group(2) for dependency in dependencies]
        # for subsystems without dependencies
        # they will appear in the order at an arbitrary point
        sorter.add(subsystem)
        for dependency in dependencies:
            # sorted dependencies are union of added dependencies
            # sorter will also auto-create previously not specified nodes with 0 dependencies and update them when its their turn
            sorter.add(subsystem, dependency)

    sorted_entries = list(sorter.static_order())
    

    logging.info(f"Topologically sorted load order: {sorted_entries}")
    logging.info(f"Total exported symbols: {num_exported} imported subsystem calls: {num_imported}")
    return sorted_entries

def get_compressed_binary(llext_dir:str, name_pattern:str)->list[str]:
    # can be one level higher for main()
    found_entries = glob.glob(f"{llext_dir}/../**/{name_pattern}._stripped_compressed", recursive=True)
    return found_entries[0]


def generate_header(sorted_entries:list[str], outfile: str)->None:
    header = \
'''#ifndef SKADI_INIT_ORDER_H
#define SKADI_INIT_ORDER_H

#include <stdbool.h>
#include <stdint.h>
#include <zephyr/skadi/skadi_loader.h>
#include <zephyr/logging/log.h>

static void skadi_subsystem_loaded(const char *subsystem_name);

'''

    for entry in sorted_entries:
        header += f"    static const uint8_t {entry}_elf[] = {{\n"
        header += f"        #include \"{entry}_ext.inc\"\n"
        header += f"    }};\n"

    header += '''
    static inline bool skadi_init_load_subsystems_in_order(void){
        LOG_MODULE_DECLARE(skadi_submodule_init, CONFIG_SKADI_LOG_LEVEL);
        LOG_INF("Starting initialization of subsystems!");
'''

    for entry in sorted_entries:
        header += f"        LOG_INF(\"Loading subsystem {entry}\");\n"
        header += f"        if(skadi_loader_load_subsystem(\"{entry}\", {entry}_elf, ARRAY_SIZE({entry}_elf)) == false){{\n"
        header += f"            LOG_ERR(\"Could not load subsystem {entry}!\");\n"
        header += f"            return false;\n"
        header += f"        }}\n"
        header += f"        skadi_subsystem_loaded(\"{entry}\");"

       
    
    header += '''
        LOG_INF("Finished initialization of subsystems!");
        return true;
    }

#endif
    '''

    with(open(outfile,"w") as file):
        file.write(header)
    
    logging.debug(f"Created output header {outfile}!")

def generate_out_dir(sd_dir_out: str, llext_dir: str, sorted_entries:list[str])->None:
    manifest_str="\n".join(sorted_entries)
    if not os.path.exists(sd_dir_out):
        os.makedirs(sd_dir_out)
    with open(os.path.join(sd_dir_out, "manifest.txt"), "w") as manifest:
        manifest.write(manifest_str)
    for entry in sorted_entries:
        llext = get_compressed_binary(llext_dir, entry)
        shutil.copy(llext, os.path.join(sd_dir_out, f"{entry}.llext"))

def main():
    # prints many instances of an error, indicating that RISC-V relocations are unsupported
    lief.logging.disable()
    outfile,sd_dir_out,llext_dir = parse_args()
    llext_binaries = get_llext_binaries(llext_dir)
    sorted_entries=sort(llext_binaries)
    generate_header(sorted_entries, outfile)
    generate_out_dir(sd_dir_out, llext_dir, sorted_entries)
    

if __name__ == "__main__":
    main()
