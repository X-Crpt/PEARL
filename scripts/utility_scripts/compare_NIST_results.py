#!/usr/bin/env python3

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

import csv
import os
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Patch
from matplotlib.lines import Line2D


ALPHA = 0.01
UNIFORMITY_THRESHOLD = 0.0001
TOTAL_PASS_RATE_MARKER_SIZE = 22
TOTAL_PASS_RATE_OUT_OF_SCALE_MARKER_SIZE = 34
TOTAL_PASS_RATE_GROUP_HALF_WIDTH = 0.30


def comparison_colors(labels):
    base_colors = list(plt.get_cmap("tab10").colors)
    extra_colors = list(plt.get_cmap("tab20").colors)
    color_cycle = []

    for color in base_colors + extra_colors:
        if color not in color_cycle:
            color_cycle.append(color)

    return {
        label: color_cycle[index % len(color_cycle)]
        for index, label in enumerate(labels)
    }


def find_project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def usage():
    print(
        "Usage: compare_NIST_results.py -module <name> [-variant <name>] "
        "-module <name> [-variant <name>] [options]\n"
        "\n"
        "Required:\n"
        "  -module <name>       Module to compare. Can be repeated. Use at least two modules.\n"
        "\n"
        "Optional:\n"
        "  -variant <name>      Variant for the previous -module. Default: default.\n"
        "  -output <path>       Output base file. Default: NIST_test/plots/NIST_comparison.png.\n"
        "  -stream_num <num>    Number of NIST streams used to generate the results. Default: 10.\n"
        "  -include_averages    Add average bars for chi-square and uniformity plots.\n"
    )


def parse_args(argv):
    datasets = []
    output = os.environ.get("NIST_comparisonPlot", "")
    stream_num = 10
    include_averages = False

    i = 1
    while i < len(argv):
        arg = argv[i]

        if arg == "-module":
            if i + 1 >= len(argv):
                raise ValueError("ERROR: -module requires a module name")
            datasets.append({"module": argv[i + 1], "variant": "default"})
            i += 2
        elif arg == "-variant":
            if i + 1 >= len(argv):
                raise ValueError("ERROR: -variant requires a variant name")
            if not datasets:
                raise ValueError("ERROR: -variant must follow a -module")
            datasets[-1]["variant"] = argv[i + 1]
            i += 2
        elif arg == "-output":
            if i + 1 >= len(argv):
                raise ValueError("ERROR: -output requires a file path")
            output = argv[i + 1]
            i += 2
        elif arg == "-stream_num":
            if i + 1 >= len(argv):
                raise ValueError("ERROR: -stream_num requires a number")
            stream_num = int(argv[i + 1])
            i += 2
        elif arg == "-include_averages":
            include_averages = True
            i += 1
        elif arg in ("-h", "-help", "--help"):
            usage()
            sys.exit(0)
        else:
            raise ValueError(f"ERROR: unknown option: {arg}")

    if len(datasets) < 2:
        raise ValueError("ERROR: at least two -module entries are required")

    return datasets, output, stream_num, include_averages


def summary_path(project_root: Path, module_name: str, variant_name: str) -> Path:
    return (
        project_root
        / "NIST_test"
        / module_name
        / variant_name
        / "plots"
        / "uniformity_summary.csv"
    )


def read_summary_csv(file_path: Path):
    data = {}

    with file_path.open(mode="r", encoding="utf-8", newline="") as csv_file:
        reader = csv.DictReader(csv_file)
        for row in reader:
            test_name = row["test_name"]
            data[test_name] = {
                "pass_rate": float(row["pass_rate"]),
                "minimum_pass_rate": float(row["minimum_pass_rate"]),
                "uniformity_p_value": float(row["uniformity_p_value"]),
                "total_count": int(row["total_count"]),
                "passed_count": int(row["passed_count"]),
                "chi_square": float(row["chi_square"]),
                "pass_rate_passed": row["pass_rate_passed"].lower() == "true",
                "uniformity_passed": row["uniformity_passed"].lower() == "true",
            }

    return data


def label_for(module_name: str, variant_name: str) -> str:
    if variant_name == "default":
        return module_name
    return f"{module_name}/{variant_name}"


def _plot_single_metric(ax, x, all_tests, datasets, labels, width, metric):
    colors = comparison_colors(labels)

    for i, (data, label) in enumerate(zip(datasets, labels)):
        values = [data.get(test, {}).get(metric, 0) for test in all_tests]

        offset = (i - (len(datasets) - 1) / 2) * width
        rects = ax.bar(
            x + offset,
            values,
            width,
            label=label,
            edgecolor="black",
            color=colors[label],
        )

        if metric == "uniformity_p_value":
            for rect, test_name in zip(rects, all_tests):
                result = data.get(test_name, {})
                if not result.get("uniformity_passed", True):
                    rect.set_edgecolor("tab:red")
                    rect.set_linewidth(1.8)
                    rect.set_hatch("//")

    if metric == "chi_square":
        ax.set_title("Chi-Square Values")
    elif metric == "uniformity_p_value":
        ax.set_title("Uniformity p-Values")
    else:
        ax.set_title(metric.replace("_", " ").title())

    ax.set_ylabel(metric.replace("_", " ").title())
    ax.set_xticks(x)
    ax.set_xticklabels(all_tests, rotation=45, ha="right")
    ax.grid(axis="y", linestyle="--", alpha=0.7)
    ax.legend()

    if "p_value" in metric:
        ax.set_ylim(0, 1.1)

    if metric == "uniformity_p_value":
        ax.axhline(
            UNIFORMITY_THRESHOLD,
            color="tab:red",
            linestyle="--",
            linewidth=1.2,
            label=f"Uniformity threshold ({UNIFORMITY_THRESHOLD:g})",
        )
        handles, legend_labels = ax.get_legend_handles_labels()
        handles.append(
            Patch(
                facecolor="white",
                edgecolor="tab:red",
                hatch="//",
                label="Failed uniformity check",
            )
        )
        legend_labels.append("Failed uniformity check")
        ax.legend(handles, legend_labels)


def _plot_pass_rate_metric(ax, x, all_tests, datasets, labels):
    y_min, y_max = 87.0, 101.5
    colors = comparison_colors(labels)
    point_offsets = np.linspace(
        -TOTAL_PASS_RATE_GROUP_HALF_WIDTH,
        TOTAL_PASS_RATE_GROUP_HALF_WIDTH,
        len(datasets),
    )

    for i, (data, label) in enumerate(zip(datasets, labels)):
        color = colors[label]
        offset_factor = point_offsets[i]
        first_point = True

        for idx, test_name in enumerate(all_tests):
            result = data.get(test_name, {})
            pass_rate = result.get("pass_rate", 0)
            passed = result.get("pass_rate_passed", True)
            marker = "o" if passed else "x"
            current_x = x[idx] + offset_factor
            legend_label = label if first_point else ""

            if pass_rate < y_min:
                ax.scatter(
                    current_x,
                    y_min,
                    marker="x",
                    color=color,
                    s=TOTAL_PASS_RATE_OUT_OF_SCALE_MARKER_SIZE,
                    linewidths=1.5,
                    zorder=3,
                    clip_on=False,
                    label=legend_label,
                )
            else:
                ax.scatter(
                    current_x,
                    pass_rate,
                    color=color,
                    marker=marker,
                    s=TOTAL_PASS_RATE_MARKER_SIZE,
                    zorder=3,
                    label=legend_label,
                )

            first_point = False

    for idx, test_name in enumerate(all_tests):
        minimum_values = [
            data[test_name]["minimum_pass_rate"]
            for data in datasets
            if test_name in data
        ]
        if not minimum_values:
            continue

        minimum_pass_rate = max(minimum_values)
        ax.hlines(
            minimum_pass_rate,
            x[idx] - 0.42,
            x[idx] + 0.42,
            color="tab:red",
            linestyle="--",
            linewidth=1.1,
            label="Minimum pass rate" if idx == 0 else None,
            zorder=2,
        )

    for separator_x in np.arange(len(all_tests) - 1) + 0.5:
        ax.axvline(
            separator_x,
            color="black",
            linestyle="--",
            linewidth=0.45,
            alpha=0.35,
            zorder=0,
        )

    expected_pass_rate = 100.0 * (1.0 - ALPHA)
    ax.axhline(
        expected_pass_rate,
        color="tab:green",
        linestyle=":",
        linewidth=1.4,
        label=f"1 - alpha ({expected_pass_rate:.2f}%)",
        zorder=1,
    )

    ax.set_title("Total Pass Rate per Test")
    ax.set_xlabel("Statistical test")
    ax.set_ylabel("Passed bitstreams [%]")
    ax.set_ylim(y_min, y_max)
    ax.set_xlim(-0.55, len(all_tests) - 0.45)
    ax.set_xticks(x)
    ax.set_xticklabels(all_tests, rotation=45, ha="right")
    ax.grid(axis="y", linestyle="--", alpha=0.4)
    handles, legend_labels = ax.get_legend_handles_labels()
    handles.append(
        Line2D(
            [0],
            [0],
            marker="x",
            color="black",
            linestyle="None",
            markersize=6,
            markeredgewidth=1.5,
            label="Pass rate failed",
        )
    )
    legend_labels.append("Pass rate failed")
    ax.legend(handles, legend_labels, loc="lower left")


def _plot_metric_with_average(x, all_tests, datasets, labels, width, metric):
    fig, (ax1, ax2) = plt.subplots(
        1,
        2,
        figsize=(16, 7),
        sharey=True,
        gridspec_kw={"width_ratios": [max(len(all_tests), 1), 2]},
    )

    _plot_single_metric(ax1, x, all_tests, datasets, labels, width, metric)

    x_avg = np.array([0])
    colors = comparison_colors(labels)

    for i, data in enumerate(datasets):
        values = [
            data.get(test, {}).get(metric, 0)
            for test in all_tests
        ]
        average = np.mean(values) if values else 0
        offset = (i - (len(datasets) - 1) / 2) * width
        rects = ax2.bar(
            x_avg + offset,
            [average],
            width,
            label=labels[i],
            edgecolor="black",
            color=colors[labels[i]],
        )
    ax2.set_xticks(x_avg)
    ax2.set_xticklabels(["Average"], rotation=45, ha="right")
    ax2.grid(axis="y", linestyle="--", alpha=0.7)
    return fig


def plot_comparison(datasets, labels, output_path, metrics, include_averages=False):
    all_tests = sorted(list(set().union(*(data.keys() for data in datasets))))
    x = np.arange(len(all_tests))
    width = 0.8 / len(datasets)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    base_name = output_path.stem
    output_dir = output_path.parent

    for metric in metrics:
        if metric == "pass_rate":
            fig, ax = plt.subplots(1, 1, figsize=(14, 7))
            _plot_pass_rate_metric(ax, x, all_tests, datasets, labels)
        elif metric in ["uniformity_p_value", "chi_square"] and include_averages:
            fig = _plot_metric_with_average(x, all_tests, datasets, labels, width, metric)
        else:
            fig, ax = plt.subplots(1, 1, figsize=(14, 7))
            _plot_single_metric(ax, x, all_tests, datasets, labels, width, metric)

        output_file = output_dir / f"{base_name}_{metric}.png"
        plt.tight_layout()
        plt.savefig(output_file, dpi=200)
        print(f"Saved NIST comparison plot: {output_file}")
        plt.close(fig)


def main():
    project_root = find_project_root()

    try:
        requested_results, output_path, _stream_num, include_averages = parse_args(sys.argv)
    except Exception as error:
        print(error, file=sys.stderr)
        usage()
        return 1

    if not output_path:
        output_path = project_root / "NIST_test" / "plots" / "NIST_comparison.png"
    else:
        output_path = Path(output_path)

    datasets = []
    labels = []

    for result in requested_results:
        module_name = result["module"]
        variant_name = result["variant"]
        result_file = summary_path(project_root, module_name, variant_name)

        if not result_file.is_file():
            print(f"ERROR: NIST summary not found: {result_file}", file=sys.stderr)
            return 1

        datasets.append(read_summary_csv(result_file))
        labels.append(label_for(module_name, variant_name))

    requested_metrics = ["chi_square", "uniformity_p_value", "pass_rate"]
    plot_comparison(datasets, labels, output_path, requested_metrics, include_averages)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
