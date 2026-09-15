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


def find_project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def display_path(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def read_sim_performance(sim_folder: Path):
    performance = {}

    for performance_file in sorted(sim_folder.glob("*/*/reports/performance.csv")):
        relative_parts = performance_file.relative_to(sim_folder).parts
        if len(relative_parts) < 4:
            continue

        module_name = relative_parts[0]
        variant_name = relative_parts[1]

        with performance_file.open(newline="") as csv_file:
            rows = list(csv.DictReader(csv_file))

        if not rows:
            print(f"WARNING: empty performance file: {performance_file}", file=sys.stderr)
            continue

        row = rows[0]
        try:
            output_bits = float(row["output_bits"])
            cycles = float(row["cycles"])
            valid_outputs = float(row["valid_outputs"])
            cycles_per_generation = float(row["cycles_per_generation"])
            bits_per_cycle = float(row["bits_per_cycle"])
        except KeyError as error:
            print(f"WARNING: missing column {error} in {performance_file}", file=sys.stderr)
            continue
        except ValueError:
            print(f"WARNING: invalid numeric value in {performance_file}", file=sys.stderr)
            continue

        performance[(module_name, variant_name)] = {
            "output_bits": output_bits,
            "cycles": cycles,
            "valid_outputs": valid_outputs,
            "cycles_per_generation": cycles_per_generation,
            "bits_per_cycle": bits_per_cycle,
        }

    return performance


def read_asic_summaries(synth_folder: Path, sim_performance):
    points = []

    for summary_file in sorted(synth_folder.glob("*/*/ASIC/reports/summary.csv")):
        relative_parts = summary_file.relative_to(synth_folder).parts
        if len(relative_parts) < 5:
            continue

        module_name = relative_parts[0]
        variant_name = relative_parts[1]

        with summary_file.open(newline="") as csv_file:
            rows = list(csv.DictReader(csv_file))

        if not rows:
            print(f"WARNING: empty summary file: {summary_file}", file=sys.stderr)
            continue

        row = rows[0]
        try:
            area = float(row["area"]) / 1000.0
            critical_path = float(row["critical_path"])
        except KeyError as error:
            print(f"WARNING: missing column {error} in {summary_file}", file=sys.stderr)
            continue
        except ValueError:
            print(f"WARNING: invalid numeric value in {summary_file}", file=sys.stderr)
            continue

        performance = sim_performance.get((module_name, variant_name))
        if performance is None:
            print(
                f"WARNING: missing simulation performance for {module_name}/{variant_name}; skipping point",
                file=sys.stderr,
            )
            continue

        if critical_path <= 0 or performance["bits_per_cycle"] <= 0:
            print(f"WARNING: invalid performance point in {summary_file}", file=sys.stderr)
            continue

        fmax_hz = 1.0e9 / critical_path
        throughput_bps = performance["bits_per_cycle"] * fmax_hz
        throughput_gbps = throughput_bps / 1.0e9

        points.append(
            {
                "module": module_name,
                "variant": variant_name,
                "area": area,
                "critical_path": critical_path,
                "fmax_hz": fmax_hz,
                "throughput_bps": throughput_bps,
                "throughput_gbps": throughput_gbps,
                **performance,
                "label": f"{module_name}/{variant_name}",
            }
        )

    return points


def pareto_front(points):
    front = []

    for point in sorted(points, key=lambda item: (item["area"], -item["throughput_bps"])):
        dominated = False
        for other in points:
            better_or_equal = (
                other["area"] <= point["area"]
                and other["throughput_bps"] >= point["throughput_bps"]
            )
            strictly_better = (
                other["area"] < point["area"]
                or other["throughput_bps"] > point["throughput_bps"]
            )
            if better_or_equal and strictly_better:
                dominated = True
                break

        if not dominated:
            front.append(point)

    return front


def label_colors(points):
    color_cycle = plt.get_cmap("tab10").colors
    labels = sorted({point["label"] for point in points})
    return {
        label: color_cycle[index % len(color_cycle)]
        for index, label in enumerate(labels)
    }


def add_better_direction_guides(ax):
    guide_style = {
        "arrowstyle": "->",
        "color": "#333333",
        "linewidth": 1.2,
        "shrinkA": 0,
        "shrinkB": 0,
    }

    ax.annotate(
        "better: lower area",
        xy=(0.02, -0.14),
        xytext=(0.24, -0.14),
        xycoords="axes fraction",
        textcoords="axes fraction",
        ha="left",
        va="center",
        fontsize=9,
        color="#333333",
        arrowprops=guide_style,
        annotation_clip=False,
    )
    ax.annotate(
        "better: higher throughput",
        xy=(-0.12, 0.95),
        xytext=(-0.12, 0.72),
        xycoords="axes fraction",
        textcoords="axes fraction",
        ha="center",
        va="center",
        rotation=90,
        fontsize=9,
        color="#333333",
        arrowprops=guide_style,
        annotation_clip=False,
    )


def plot_pareto(points, output_file: Path):
    output_file.parent.mkdir(parents=True, exist_ok=True)

    fig, ax = plt.subplots(figsize=(11, 6))

    front = pareto_front(points)
    front = sorted(front, key=lambda point: point["area"])
    if len(front) >= 2:
        ax.plot(
            [point["area"] for point in front],
            [point["throughput_gbps"] for point in front],
            color="#222222",
            linestyle="--",
            linewidth=1.7,
            label="Pareto front",
            zorder=1,
        )
    elif len(front) == 1:
        ax.scatter(
            [front[0]["area"]],
            [front[0]["throughput_gbps"]],
            color="#222222",
            s=80,
            label="Pareto front",
            zorder=1,
        )

    colors = label_colors(points)
    for point in sorted(points, key=lambda item: item["label"]):
        ax.scatter(
            point["area"],
            point["throughput_gbps"],
            color=colors[point["label"]],
            edgecolors="black",
            linewidths=0.4,
            s=65,
            label=point["label"],
            zorder=3,
        )

    ax.set_title("ASIC Pareto: Area vs Throughput")
    ax.set_xlabel(r"Cell area ($10^3\,\mu m^2$)")
    ax.set_ylabel("Throughput (Gbit/s)")
    ax.grid(True, linestyle="--", linewidth=0.5, alpha=0.5)
    add_better_direction_guides(ax)
    fig.subplots_adjust(left=0.12, bottom=0.18)
    ax.legend(loc="center left", bbox_to_anchor=(1.02, 0.5), borderaxespad=0.0)
    fig.tight_layout()
    fig.savefig(output_file, dpi=200, bbox_inches="tight")
    plt.close(fig)


def main():
    project_root = find_project_root()
    synth_folder = Path(os.environ.get("SYNTH_FOLDER", project_root / "synth"))
    sim_folder = Path(os.environ.get("SIM_RESULTS_FOLDER", project_root / "sim"))
    output_file = Path(
        os.environ.get("PLOT_SYNTH_ASIC_PARETO", synth_folder / "plots" / "pareto_asic.png")
    )

    sim_performance = read_sim_performance(sim_folder)
    if not sim_performance:
        print(f"ERROR: no performance.csv files found in {sim_folder}", file=sys.stderr)
        return 1

    points = read_asic_summaries(synth_folder, sim_performance)
    if not points:
        print(
            f"ERROR: no matching ASIC summary.csv and performance.csv files found in {synth_folder}",
            file=sys.stderr,
        )
        return 1

    plot_pareto(points, output_file)
    print(f"Saved ASIC Pareto plot: {display_path(output_file, project_root)}")
    print(f"Parsed points: {len(points)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
