#!/usr/bin/env python3
#
# Copyright (c) 2023 KNS Group LLC (YADRO)
# Copyright (c) 2020 Yonatan Goldschmidt <yon.goldschmidt@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

"""
Stack compressor for FlameGraph (Skadi version)

This translate stack samples captured by perf subsystem into format
used by flamegraph.pl. Translation uses .elf/.llext files to get function names
from addresses

Usage:
    ./script/perf/stackcollapse.py <file with perf printbuf output> <ELF file>
"""

import sys
import struct
import binascii
from elftools.elf.elffile import ELFFile
from os import listdir
from os.path import isfile, join
from re import compile
from tempfile import NamedTemporaryFile



def addr_to_sym_real(addr, subsystems):
    for elf,text_base in subsystems:
        text_section = elf.get_section_by_name(".text")
        text_size = text_section.data_size
        if addr < text_base or addr >= text_base + text_size:
            # NOT this subsystem
            continue
        symtab = elf.get_section_by_name(".symtab")
        for sym in symtab.iter_symbols():
            if sym.entry.st_info.type == "STT_FUNC" and text_base + sym.entry.st_value <= addr < text_base + sym.entry.st_value + sym.entry.st_size:
                return sym.name
    if addr == 0:
        return None
    return None

sym_cache = {}
def addr_to_sym(addr, subsystems):
    if not addr in sym_cache:
        sym_cache[addr] = addr_to_sym_real(addr, subsystems)
    return sym_cache[addr]

def collapse(buf, subsystems, number_invok):
    with NamedTemporaryFile(delete=False) as tmp:
        while buf:
            count, = struct.unpack_from(">Q", buf)
            assert count > 0
            addrs = struct.unpack_from(f">{count}Q", buf, 8)
            func_trace = map(lambda a: addr_to_sym(a, subsystems), addrs)
            func_trace = filter(lambda a: a is not None, func_trace)
            func_trace = list(func_trace)
            if not len(func_trace):
                print("Skip")
                buf = buf[8 + 8 * count:]
                continue
            func_trace = reversed(func_trace)
            prev_func = next(func_trace)
            line = prev_func
            # merge dublicate functions
            for func in func_trace:
                if prev_func != func:
                    prev_func = func
                    line += ";" + func
            line = line+" 1\n"
            tmp.write(line.encode("ascii"))
            buf = buf[8 + 8 * count:]
    print(f"Sample {number_invok} is at {tmp.name}")


if __name__ == "__main__":
    subsystems = []
    elf_files = []
    line_regex = r"^I: skadi_debug_subsystem ([a-zA-Z0-9_]+) 0x([0-9a-f]+).*$"
    line_regex = compile(line_regex)

    llext_dir = sys.argv[2]

    with open(sys.argv[1], "r") as f:
        inp = f.read()
    lines = inp.splitlines()

    try:
        for file in listdir(llext_dir):
            if(isfile(join(llext_dir,file))):
                if(file.endswith(".llext")):
                    elf_file = open(join(llext_dir,file),"rb")
                    elf_files.append(elf_file)
                    elf = ELFFile(elf_file, "rb")
                    found_offset = 0

                    for line in lines:
                        match = line_regex.match(line)
                        if(match):
                            subsys_name = match.group(1)
                            text_offset = int(match.group(2), base=16)
                            if(subsys_name+".llext" == file):
                                found_offset = text_offset
                                break
                    if found_offset == 0:
                        print(f"Did not find text offset for subsystem {file}")

                    subsystems += [(elf, found_offset)]

        lines_iter = iter(lines)
        sample_num = 1
        for line in lines_iter:
            sample = []
            if(line == "--- SKADI PERF START ---"):
                line = next(lines_iter)
                while line != "--- SKADI PERF END ---":
                    sample.append(line)
                    line = next(lines_iter)
                if len(sample):
                    buf = binascii.unhexlify("".join(sample))
                    collapse(buf, subsystems, sample_num)
                    sample_num = sample_num + 1
    finally:
        for file in elf_files:
            file.close()
