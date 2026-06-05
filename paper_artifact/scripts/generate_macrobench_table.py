import re
from itertools import zip_longest

# Define the filenames
filenames_genesys2 = ['raw_eval_data/genesys2/rt_macrobench_zephyr_cva6.txt', 'raw_eval_data/genesys2/rt_macrobench_zephyr_northcape.txt', 'raw_eval_data/genesys2/rt_macrobench_skadi_northcape.txt']
filenames_arty = ['raw_eval_data/arty_a7_100/rt_macrobench_zephyr_northcape.txt','raw_eval_data/arty_a7_100/rt_macrobench_skadi_northcape.txt', 'raw_eval_data/arty_a7_100/rt_macrobench_skadi_northcape.txt']

# Define the regex pattern
pattern = re.compile(r'^(.+) discarded/min/max/avg/stddev ns: (\d+)/(\d+)/(\d+)/(\d+(\.\d+)?)/(\d+(\.\d+)?)$')


# Generator function to read and filter lines from a file
def read_and_filter_lines(filename, pattern):
    with open(filename, 'r') as file:
        for line in file:
            match = pattern.search(line)
            if match:
                if not "(Samples)" in line:
                    continue
                result = dict(name=match.group(1), discarded=match.group(2), min=match.group(3), max=match.group(4), avg=match.group(5), stddev=match.group(7))
                yield result

def format_cell(cell: [str])->[str]:
    cell = cell.split("/")
    cell = [f"\\num{{{col}}}" for col in cell]
    cell = ' / '.join(cell)
    return cell
    
def create_table_header_long(board: str)->str:
    table_header_genesys2='''
\\onecolumn
\\topcaption{Detailed results from scheduler macrobenchmark on Genesys 2 board. We benchmark performance in three scenarios: Zephyr running on the original cva6, Zephyr running on the Northcape SoC where Northcape is deactivated and Skadi running on the Northcape SoC. Names are as used in original Zephyr benchmark.}
\\label{tab:macrobenchmark_full}
\\begin{supertabular}{|p{4cm}|p{4cm}|p{4cm}|p{4cm}|}
\\hline
Macrobechmark & Zephyr cva6 \\newline min/max/avg/stddev ns & Zephyr Northcape SoC \\newline min/max/avg/stddev ns & Skadi Northcape SoC \\newline min/max/avg/stddev ns\\\\
\\hline
    '''
    table_header_arty='''
\\onecolumn
\\topcaption{Detailed results from scheduler macrobenchmark on Arty A7 board. We benchmark performance in three scenarios: Zephyr running on the original cva6, Zephyr running on the Northcape SoC where Northcape is deactivated and Skadi running on the Northcape SoC. Names are as used in original Zephyr benchmark.}
\\label{tab:macrobenchmark_full_arty}
\\begin{supertabular}{|p{4cm}|p{6cm}|p{6cm}|}
\\hline
Macrobechmark & Zephyr Northcape SoC \\newline min/max/avg/stddev ns & Skadi Northcape SoC \\newline min/max/avg/stddev ns\\\\
\\hline
    '''
    return table_header_genesys2 if board == 'genesys2' else table_header_arty



def create_table(board: str):
    if board == "genesys2":
        filenames = filenames_genesys2
    else:
        filenames = filenames_arty
 
    # Create generators for each file
    generators = [read_and_filter_lines(filename, pattern) for filename in filenames]
    
    with open(f"tables/0a_macrobench_table_{board}.tex","w") as file:
        file.write(create_table_header_long(board))
        results = 0

        diffs={
            "min": (0,0),
            "min_name": (None, None),
            "max": (0,0),
            "max_name": (None,None),
            "avg": (0,0),
            "avg_name": (None,None),
            "stddev": (0,0),
            "stddev_name": (None, None)
        }

        is_first = True
        table_footer = '''  \\end{supertabular}
\\twocolumn
    '''
        line_num = 0
        # Iterate over the filtered lines from all three files
        for result1, result2, result3 in zip_longest(*generators, fillvalue=''):
            line_num = line_num + 1
            print(f"{line_num} {result1} {result2} {result3}")
            cell_name = result1["name"].replace("(Samples)","")
            cell_name = cell_name.replace("_","\\_")
            cell_name = cell_name.replace(".",".\\allowbreak ")
            cell_cva6 = f"{result1['min']} / {result1['max']} / {result1['avg']} / {result1['stddev']}"
            cell_Zephyr = f"{result2['min']} / {result2['max']} / {result2['avg']} / {result2['stddev']}"
            cell_skadi = f"{result3['min']} / {result3['max']} / {result3['avg']} / {result3['stddev']}"

            for key in ["min", "max", "avg", "stddev"]:
                diff = abs(float(result3[key]) - float(result2[key]))
                if is_first or diffs[key][0][0] > diff:
                    original_tuple = diffs[key]
                    diffs[key] = ((diff, float(result3[key]), float(result2[key])), original_tuple[1])
                    original_tuple = diffs[f"{key}_name"]
                    diffs[f"{key}_name"] = (cell_name, original_tuple[1])
                if is_first or diffs[key][1][0] < diff:
                    original_tuple = diffs[key]
                    diffs[key] = (original_tuple[0], (diff, float(result3[key]), float(result2[key])))
                    original_tuple = diffs[f"{key}_name"]
                    diffs[f"{key}_name"] = (original_tuple[0],cell_name)

            is_first = False

            if result1["name"] != result2["name"] or result1["name"] != result2["name"]:
                print(f"WRN: Name disagreement: {result1['name']} vs {result2['name']} vs {result3['name']}")

            cell_cva6 = format_cell(cell_cva6)
            cell_Zephyr = format_cell(cell_Zephyr)
            cell_skadi = format_cell(cell_skadi)

            if board == 'arty':
                # arty - two results ("cva6" and Zephyr are the same file)
                file.write(f"\t{cell_name} & {cell_Zephyr} & {cell_skadi}\\\\\n")
            else:
                # genesys2 - three results
                file.write(f"\t{cell_name} & {cell_cva6} & {cell_Zephyr} & {cell_skadi}\\\\\n")
            file.write(f"\t\\hline\n")
            results = results + 1
        file.write(table_footer)
        print(f"Found {results} benchmarks for board {board}!")

    table_header='''
    \\begin{table*}
        \\centering
        \\begin{tabularx}{\\linewidth}{|p{3cm}|p{3cm}|p{3cm}|p{3cm}|X|}
        \\hline
        Minimum-of & Minimum Difference ns (Zephyr / Skadi ns) & Minimum Benchmark Name & Maximum Difference ns (Zephyr / Skadi ns) & Maximum Benchmark Name\\\\
        \\hline
    '''
    table_footer='''\t\\end{tabularx}
        \\caption{Abbreviated results from latency macrobenchmark. For the categories minimum, maximum, average duration and standard deviation we list the closest and furthest apart measurements. Differences are computed between Zephyr on cva6 and Skadi on Northcape.}
        \\label{tab:real_time_macrobench}
    \\end{table*}
    '''

    with open(f"tables/0a_macrobench_short_{board}.tex","w") as file:
        file.write(table_header)
        friendly_name={
            "min": "Difference of Macrobenchmark Minimums",
            "max": "Difference of Macrobenchmark Maximums",
            "avg": "Difference of Macrobenchmark Averages",
            "stddev": "Difference of Macrobenchmark Standard Deviations"
        }
        for key in ["min", "max", "avg", "stddev"]:
            name_col = friendly_name[key]
            min_col = diffs[key][0]
            max_col = diffs[key][1]
            min_name_col = diffs[f"{key}_name"][0]
            max_name_col = diffs[f"{key}_name"][1]

            file.write(f"\t{name_col} & \\num{{{min_col[0]}}} (\\num{{{min_col[2]}}} / \\num{{{min_col[1]}}}) & {min_name_col} & \\num{{{max_col[0]}}} (\\num{{{max_col[2]}}} / \\num{{{max_col[1]}}}) & {max_name_col}\\\\\n")
            file.write("\t\\hline\n")
            min_name_col = min_name_col.split("-")[0]
            max_name_col = max_name_col.split("-")[0]
            name_col = name_col.split(" ")[-1]
            print(f"{name_col} ns: closest {min_name_col} (Zephyr: \\num{{{min_col[2]}}} / Skadi: \\num{{{min_col[1]}}}), furthest: {max_name_col}  (Zephyr \\num{{{max_col[2]}}} / Skadi \\num{{{max_col[1]}}})")
            pass
        file.write(table_footer)

create_table("genesys2")
create_table("arty")
