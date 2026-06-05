#!/usr/bin/env python3
import subprocess
import sys
from collections import defaultdict

if len(sys.argv) != 2:
    print("Usage: python3 analyze_lines.py <binary>")
    sys.exit(1)

binary = sys.argv[1]

# Adjust this command if you use a different objdump invocation
proc = subprocess.run(
    ["objdump", "--dwarf=decodedline", binary],
    stdout=subprocess.PIPE, text=True
)

file_to_lines = defaultdict(set)

for line in proc.stdout.splitlines():
    # Skip empty or header lines
    if not line.strip():
        continue

    parts = line.split()
    # Expect at least: file, line, address
    if len(parts) < 3:
        continue

    # Heuristic: last "0x..." is address, second column is line, the rest at front is file
    # But in your example, file is a single token, so we keep it simple:
    file = parts[0]
    try:
        line_no = int(parts[1])
    except ValueError:
        continue

    file_to_lines[file].add(line_no)

print("Unique source lines contributing to binary:")
total_sum = 0
for f, line_set in sorted(file_to_lines.items(), key=lambda x: -len(x[1])):
    print(f"{len(line_set):10d}  {f}")
    total_sum += len(line_set)
print(f"Total LoC: {total_sum}")
