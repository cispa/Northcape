#!/usr/bin/env python3

import argparse
import logging
import os
import sys
import subprocess
import tempfile 
import pathlib
import re

from pydevicetree import Devicetree, Node

logging.basicConfig(level=logging.INFO)



def preprocess_cv64a6_devtree(file: str, out_file: str, include_dir: str):
    if not include_dir:
        include_dir = "."
    subprocess.run(["cpp", "-x", "assembler-with-cpp", "-nostdinc", "-P", "-D__DTS__", "-E", file, "-I", include_dir, "-o", out_file])

def parse_args():
    # Returns parsed command-line arguments

    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--zephyr-dts", required=True, help="Zephyr DTS file")
    parser.add_argument("--northcape-dts", required=True,
                        help="Northcape DTs file")
    parser.add_argument("--extra-include-dir",nargs='?', const=".", help="Extra include directory")
    parser.add_argument("--ignore-node",action="extend", nargs='+', help="Nodes for which NOT to search for matching partner")
    parser.add_argument("--ignore-nodes-file",required=False, nargs='?', const=None, help="File with nodes to ignore in comparison, separated by line break.")
    return parser.parse_args()

def get_field_as_set(fieldname:str, other_node:Node):
    other_compatible = other_node.get_fields(fieldname)
    if not other_compatible:
        other_compatible = []
    try:
        return set(other_compatible)
    except Exception as e:
        logging.error(f"Could not create set of compatibles: {e}")
        return set()

def get_matching_node(node: Node, northcape_nodes: [Node]):
    compatible = get_field_as_set("compatible", node)
    interrupts = get_field_as_set("interrupts", node)
    for other_node in northcape_nodes:
        try:
            other_compatible = get_field_as_set("compatible",other_node)
            other_interrupts = get_field_as_set("interrupts", other_node)
            if not node.get_reg() or not other_node.get_reg():
                continue
            own_tuples = node.get_reg().tuples[0]
            other_tuples = other_node.get_reg().tuples[0]
            if own_tuples[0] != other_tuples[0] or own_tuples[1] != other_tuples[1]:
                logging.info(f"Reg {node.get_reg()} vs {other_node.get_reg()} does not match for node {node.get_path()} other_node {other_node.get_path()}")
                continue 
            if not compatible.intersection(other_compatible) and not compatible == set():
                logging.info(f"Compatible does not match for node {node.get_path()} other_node {other_node.get_path()}")
                continue
            if interrupts != other_interrupts:
                logging.info(f"Interrupt {interrupts} vs {other_interrupts} does not match for node {node.get_path()} other_node {other_node.get_path()}")
                continue
            return other_node
        except Exception as e:
            logging.error(f"Device Tree exception: {e} for node {node} other_node {other_node}")
            continue
    return None
def main():
    args = parse_args()

    skip_nodes=set()

    if(args.ignore_node):
        for skip_node in args.ignore_node:
            skip_nodes.add(skip_node)

    if args.ignore_nodes_file:
        with open(args.ignore_nodes_file, "r") as file:
            for line in file:
                line = line.strip()
                if(line.startswith("#")):
                    # comment line
                    continue
                skip_nodes.add(line)
    logging.info(f"Skipping nodes: {skip_nodes}")

    with open(args.northcape_dts,"r") as northcape_dts:
        # compiling/de-compiling the device tree introduces separators with \0, which pydevicetree does not understand...
        problematic_concat_pattern=re.compile("^\W*compatible\W*=\W*\".+\"\W*;\W*$")
        with tempfile.NamedTemporaryFile() as tmp_file:
            with open(tmp_file.name,"w") as write_file:
                for line in northcape_dts:
                    if problematic_concat_pattern.match(line):
                        line = line.replace("\\0","\",\"")
                    print(line,file=write_file)
            print(f"Wrote to tmp_file {tmp_file.name}")
            northcape_dt = Devicetree.parseFile(tmp_file.name)
    

    with tempfile.NamedTemporaryFile() as tmp_file:
        preprocess_cv64a6_devtree(args.zephyr_dts, tmp_file.name, args.extra_include_dir)
        zephyr_dt = Devicetree.parseFile(tmp_file.name)
        
    found_error = False
    
    for node in zephyr_dt.all_nodes():
        if node.get_field("status") != "okay":
            logging.info(f"Not comparing disabled not {node.get_path()}")
            continue
        other_node = get_matching_node(node, northcape_dt.all_nodes())
        try:
            if node.get_path() in skip_nodes:
                logging.info(f"Skipping node {node.get_path()}")
                continue
            if node.get_reg() and not node.get_field("status") == "disabled":
                logging.info(f"Searching match for node {node.get_path()}")
                # garbage nodes such as soc can be skipped
                if(other_node):
                    logging.info(f"Node {node.get_path()} has matching node {other_node.get_path()}!")
                else:
                    logging.error(f"Node {node.get_path()} has no match!")
                    found_error = True
        except Exception as e:
            logging.warn(f"Node {node.get_path()} error {e}")
    
    if(found_error):
        logging.error("Found non-matching nodes!")
        sys.exit(1)
    else:
        logging.info("All nodes match!")
        sys.exit(0)
if __name__ == "__main__":
    main()
