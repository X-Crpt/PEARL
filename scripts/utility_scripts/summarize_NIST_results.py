#!/usr/bin/env python3

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# This script reads the finalAnalysisReport.txt file produced by the NIST suite and writes a
# compact, numeric, per-test-type pass-rate summary next to the plots that plot_NIST_results.py
# already generates. It exists so that a pass-rate range (e.g. for a paper table or a quick
# sanity check) does not require re-deriving it from the raw report or from a plot image.
#
# It reuses plot_NIST_results.py's own report parser and per-test aggregation, so the two
# scripts always agree on what a "test" and a "pass rate" mean.

import csv
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from plot_NIST_results import get_aggregated_data_by_test, read_final_analysis_report  # noqa: E402


def summarize(report_file):
    """Return a list of (test_name, passed_count, total_count, pass_rate_percent, warning)."""

    nist_data = read_final_analysis_report(report_file)
    aggregated = get_aggregated_data_by_test(nist_data)

    rows = []
    for test_name, values in aggregated.items():
        total_count = values["total_count"]
        if total_count == 0:
            continue
        pass_rate_percent = 100.0 * values["passed_count"] / total_count
        rows.append((test_name, values["passed_count"], total_count, pass_rate_percent, values["warning"]))

    rows.sort(key=lambda row: row[3])
    return rows


def write_csv(rows, output_file):
    with open(output_file, "w", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["test_name", "passed_count", "total_count", "pass_rate_percent", "warning"])
        for test_name, passed_count, total_count, pass_rate_percent, warning in rows:
            writer.writerow([test_name, passed_count, total_count, f"{pass_rate_percent:.4f}", int(warning)])


def main():
    # The bash script gives the paths to Python, matching plot_NIST_results.py's convention.
    # Example:
    # python3 scripts/utility_scripts/summarize_NIST_results.py finalAnalysisReport.txt summary.csv
    if len(sys.argv) != 3:
        print(
            "Usage: python3 summarize_NIST_results.py "
            "<finalAnalysisReport.txt> <pass_rate_summary.csv>"
        )
        sys.exit(1)

    report_file = Path(sys.argv[1])
    output_csv = Path(sys.argv[2])

    rows = summarize(report_file)
    if not rows:
        print("No test records with a non-zero stream count were found in the report.")
        sys.exit(1)

    write_csv(rows, output_csv)

    pass_rates = [row[3] for row in rows]
    print(f"Per-test-type pass rate range: {min(pass_rates):.1f}%--{max(pass_rates):.1f}% "
          f"across {len(rows)} test types.")
    warned = [row[0] for row in rows if row[4]]
    if warned:
        print(f"Test types with at least one flagged sub-test: {', '.join(sorted(set(warned)))}")
    print(f"Saved pass-rate summary: {output_csv}")


if __name__ == "__main__":
    main()
