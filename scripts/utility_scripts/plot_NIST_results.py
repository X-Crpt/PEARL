#!/usr/bin/env python3

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# This script reads the finalAnalysisReport.txt file produced by the NIST suite
# and creates a simple plot with matplotlib.
#
# For now we make one plot:
# total pass percentage for each statistical test.

import math
from pathlib import Path
import re
import sys

import matplotlib.pyplot as plt


ALPHA = 0.01
TOTAL_PASS_RATE_MIN_LINE_POSITION = 0.30
TOTAL_PASS_RATE_LABEL_SIZE = 9
TOTAL_PASS_RATE_TOP_MARGIN = 1.0
TOTAL_PASS_RATE_OUT_OF_SCALE_LABEL_POSITION = 0.02
UNIFORMITY_PASS_LIMIT = 0.0001
UNIFORMITY_BAR_WIDTH = 0.085
GAMMA_EPSILON = 0.00000000000001
GAMMA_MAX_ITERATIONS = 1000
GAMMA_SMALL_NUMBER = 0.000000000000000000000000000001


def calculate_total_pass_rate_y_limits(minimum_pass_rate):
    """Calculate Y limits with the minimum pass rate at 30 percent of the plot height."""

    # The graph must show a little space over 100%, otherwise labels are too close to the border.
    y_max = 100.0 + TOTAL_PASS_RATE_TOP_MARGIN

    # I want the minimum pass rate line to be at 30% of the graph height.
    # Formula:
    # line_position = (minimum_pass_rate - y_min) / (y_max - y_min)
    # Then I solve it to find y_min.
    y_min = (
        minimum_pass_rate
        - TOTAL_PASS_RATE_MIN_LINE_POSITION * y_max
    ) / (1.0 - TOTAL_PASS_RATE_MIN_LINE_POSITION)

    return y_min, y_max


def calculate_minimum_pass_rate(number_of_sequences):
    """Calculate the NIST minimum pass rate for a given number of tested sequences."""

    p_hat = 1.0 - ALPHA
    return (p_hat - 3.0 * math.sqrt((p_hat * ALPHA) / number_of_sequences)) * 100.0


def gamma_upper_regularized(a_value, x_value):
    """Calculate Q(a, x), used by NIST for the p-value uniformity check."""

    # This is a small implementation of the incomplete gamma function.
    # It avoids adding scipy only for this calculation.
    if x_value < 0.0 or a_value <= 0.0:
        raise ValueError("Invalid values for incomplete gamma calculation")

    if x_value == 0.0:
        return 1.0

    # For small x, it is easier to calculate P(a, x) and then return 1 - P(a, x).
    if x_value < a_value + 1.0:
        ap_value = a_value
        delta = 1.0 / a_value
        total = delta

        for _ in range(GAMMA_MAX_ITERATIONS):
            ap_value += 1.0
            delta *= x_value / ap_value
            total += delta

            if abs(delta) < abs(total) * GAMMA_EPSILON:
                log_part = -x_value + a_value * math.log(x_value) - math.lgamma(a_value)
                lower_regularized = total * math.exp(log_part)
                return 1.0 - lower_regularized

    # For larger x, the continued fraction calculates Q(a, x) directly.
    b_value = x_value + 1.0 - a_value
    c_value = 1.0 / GAMMA_SMALL_NUMBER
    d_value = 1.0 / b_value
    h_value = d_value

    for index in range(1, GAMMA_MAX_ITERATIONS + 1):
        an_value = -index * (index - a_value)
        b_value += 2.0
        d_value = an_value * d_value + b_value

        if abs(d_value) < GAMMA_SMALL_NUMBER:
            d_value = GAMMA_SMALL_NUMBER

        c_value = b_value + an_value / c_value

        if abs(c_value) < GAMMA_SMALL_NUMBER:
            c_value = GAMMA_SMALL_NUMBER

        d_value = 1.0 / d_value
        delta = d_value * c_value
        h_value *= delta

        if abs(delta - 1.0) < GAMMA_EPSILON:
            log_part = -x_value + a_value * math.log(x_value) - math.lgamma(a_value)
            return math.exp(log_part) * h_value

    raise RuntimeError("Incomplete gamma calculation did not converge")


def get_safe_file_name(test_name):
    """Convert a test name into a simple file name."""

    safe_name = test_name.lower()
    safe_name = re.sub(r"[^a-z0-9]+", "_", safe_name)
    safe_name = safe_name.strip("_")
    return safe_name


def read_final_analysis_report(report_file):
    """Read finalAnalysisReport.txt and save the data in a list of dictionaries."""

    data = {
        "generator_file": "",
        "records": [],
    }

    with open(report_file, "r") as file:
        for line in file:
            line = line.strip()

            # This line contains the bit file used by the NIST suite.
            if line.startswith("generator is"):
                data["generator_file"] = line.replace("generator is", "").strip()
                data["generator_file"] = data["generator_file"].strip("<>")
                continue

            # Result lines start with C1..C10, so with 10 numbers.
            words = line.split()
            if len(words) < 13:
                continue

            # If the first 10 elements are not numbers, this is not a data line.
            try:
                bins = [int(value) for value in words[0:10]]
            except ValueError:
                continue

            # After the 10 bins, I find the p-value.
            # Some tests have "----" instead of the p-value.
            if words[10] == "----":
                p_value = None
            else:
                p_value = float(words[10])

            current_index = 11

            # If there is a star after the p-value, the NIST suite is giving a warning.
            p_value_warning = False
            if words[current_index] == "*":
                p_value_warning = True
                current_index += 1

            # The proportion is written like 98/100.
            # Sometimes NIST writes ------ when a test is undefined, so I skip that row.
            proportion_index = -1
            for index in range(current_index, len(words)):
                if "/" in words[index]:
                    proportion_index = index
                    break

            if proportion_index == -1:
                continue

            passed_text, total_text = words[proportion_index].split("/")
            passed_count = int(passed_text)
            total_count = int(total_text)
            current_index = proportion_index + 1

            # There can also be a star after the proportion.
            proportion_warning = False
            if current_index < len(words) and words[current_index] == "*":
                proportion_warning = True
                current_index += 1

            # The test name is the last part of the line.
            test_name = " ".join(words[current_index:])

            record = {
                "bins": bins,
                "p_value": p_value,
                "passed_count": passed_count,
                "total_count": total_count,
                "test_name": test_name,
                "p_value_warning": p_value_warning,
                "proportion_warning": proportion_warning,
            }

            data["records"].append(record)

    return data


def get_aggregated_data_by_test(data):
    """Aggregate bins, pass counts and warnings for every test name."""
    aggregated = {}

    for record in data["records"]:
        test_name = record["test_name"]

        if test_name not in aggregated:
            aggregated[test_name] = {
                "bins": [0] * 10,
                "passed_count": 0,
                "total_count": 0,
                "warning": False
            }

        for index in range(10):
            aggregated[test_name]["bins"][index] += record["bins"][index]
        aggregated[test_name]["passed_count"] += record["passed_count"]
        aggregated[test_name]["total_count"] += record["total_count"]
        if record["p_value_warning"] or record["proportion_warning"]:
            aggregated[test_name]["warning"] = True

    return aggregated


def calculate_uniformity_values(bins):
    """Calculate chi-square and the uniformity p-value for one test."""

    total_count = sum(bins)

    if total_count == 0:
        return None, None, False

    expected_count = total_count / 10.0
    chi_square = 0.0

    for observed_count in bins:
        chi_square += ((observed_count - expected_count) ** 2) / expected_count

    # NIST uses igamc(9/2, chi_square/2).
    uniformity_p_value = gamma_upper_regularized(9.0 / 2.0, chi_square / 2.0)
    uniformity_passed = uniformity_p_value >= UNIFORMITY_PASS_LIMIT

    return chi_square, uniformity_p_value, uniformity_passed


def plot_uniformity_histograms_by_test(data, output_folder, summary_file, _number_of_streams):
    """Create one p-value bucket histogram for each test."""

    output_folder = Path(output_folder)
    summary_file = Path(summary_file)

    output_folder.mkdir(parents=True, exist_ok=True)
    summary_file.parent.mkdir(parents=True, exist_ok=True)

    aggregated_data = get_aggregated_data_by_test(data)

    with open(summary_file, "w") as file:
        file.write(
            "test_name,total_count,passed_count,pass_rate,minimum_pass_rate,"
            "pass_rate_passed,chi_square,uniformity_p_value,uniformity_passed,nist_warning\n"
        )

        for test_name, info in aggregated_data.items():
            bins = info["bins"]
            passed_count = info["passed_count"]
            total_count = info["total_count"]
            nist_warning = info["warning"]

            chi_square, uniformity_p_value, uniformity_passed = calculate_uniformity_values(bins)

            if total_count == 0:
                continue

            pass_rate = 100.0 * passed_count / total_count
            minimum_pass_rate_val = calculate_minimum_pass_rate(total_count)
            pass_rate_passed = pass_rate >= minimum_pass_rate_val

            bucket_percentages = []
            for value in bins:
                bucket_percentages.append(100.0 * value / total_count)

            file.write(
                f"{test_name},{total_count},{passed_count},{pass_rate:.2f},"
                f"{minimum_pass_rate_val:.2f},{pass_rate_passed},{chi_square:.6f},"
                f"{uniformity_p_value:.6f},{uniformity_passed},{nist_warning}\n"
            )

            if uniformity_passed:
                main_color = "tab:blue"
                status_text = "PASS"
            else:
                main_color = "tab:red"
                status_text = "FAIL"

            y_max = max(bucket_percentages) * 1.20
            if y_max < 20.0:
                y_max = 20.0

            # Each bucket represents a p-value interval:
            # 0.0-0.1, 0.1-0.2, ..., 0.9-1.0.
            # The bars are centered in the middle of each interval.
            x_values = []
            for index in range(10):
                x_values.append(0.05 + index * 0.10)

            x_ticks = []
            for index in range(11):
                x_ticks.append(index * 0.10)

            plt.figure(figsize=(8, 5))
            plt.bar(
                x_values,
                bucket_percentages,
                width=UNIFORMITY_BAR_WIDTH,
                align="center",
                color=main_color,
                edgecolor="black",
            )
            plt.axhline(10.0, color="black", linestyle="--", linewidth=1.0, label="Expected value (10%)")

            plt.title(
                f"{test_name} - p-value uniformity ({status_text})\n"
                f"chi-square = {chi_square:.3f}, uniformity p-value = {uniformity_p_value:.6f}"
            )
            plt.xlabel("P-value bucket")
            plt.ylabel("Values in bucket [%]")
            plt.xlim(0.0, 1.0)
            plt.ylim(0, y_max)
            plt.xticks(x_ticks, [f"{value:.1f}" for value in x_ticks])
            plt.grid(axis="y", linestyle="--", alpha=0.4)
            plt.legend(loc="upper right")

            plt.tight_layout()
            plt.savefig(output_folder / f"{get_safe_file_name(test_name)}_uniformity.png", dpi=200)
            plt.close()


def plot_total_pass_rate_by_test(data, output_file, _number_of_streams):
    """Create a point plot with the total pass percentage for each test."""

    # I sum the passed sequences and the total sequences for each test.
    # This gives one final percentage for every test name.
    passed_by_test = {}
    total_by_test = {}
    warning_by_test = {}

    for record in data["records"]:
        test_name = record["test_name"]

        if test_name not in passed_by_test:
            passed_by_test[test_name] = 0
            total_by_test[test_name] = 0
            warning_by_test[test_name] = False

        passed_by_test[test_name] += record["passed_count"]
        total_by_test[test_name] += record["total_count"]

        # I also remember if the NIST report marked this test with a star.
        if record["p_value_warning"] or record["proportion_warning"]:
            warning_by_test[test_name] = True

    test_names = list(passed_by_test.keys())
    pass_rates = []

    for name in test_names:
        pass_rate = 100.0 * passed_by_test[name] / total_by_test[name]
        pass_rates.append(pass_rate)

    # The NIST minimum pass rate depends on the number of tested proportions.
    # Some report rows are aggregated under the same test name, so each test can have
    # a different threshold.
    minimum_pass_rates = {}
    for name in test_names:
        minimum_pass_rates[name] = calculate_minimum_pass_rate(total_by_test[name])

    # This is the expected pass rate, because alpha is the expected fail probability.
    expected_pass_rate = 100.0 * (1.0 - ALPHA)
    y_min, y_max = calculate_total_pass_rate_y_limits(min(minimum_pass_rates.values()))

    output_file = Path(output_file)
    output_file.parent.mkdir(parents=True, exist_ok=True)

    plt.figure(figsize=(13, 6))

    x_values = list(range(len(test_names)))
    y_height = y_max - y_min
    out_of_scale_label_y = y_min + TOTAL_PASS_RATE_OUT_OF_SCALE_LABEL_POSITION * y_height

    for index, pass_rate in enumerate(pass_rates):
        test_name = test_names[index]

        # If the value is outside the zoomed Y axis, I put a red x at the bottom.
        # This means the test exists, but it is too low to be shown in the zoom.
        if pass_rate < y_min:
            plt.scatter(
                index,
                y_min,
                marker="x",
                color="tab:red",
                s=80,
                linewidths=2,
                zorder=3,
                clip_on=False,
            )
            plt.text(
                index,
                out_of_scale_label_y,
                f"{pass_rate:.1f}",
                ha="center",
                va="bottom",
                fontsize=TOTAL_PASS_RATE_LABEL_SIZE,
                color="tab:red",
            )
        else:
            if pass_rate < minimum_pass_rates[test_name]:
                point_color = "tab:red"
            else:
                point_color = "tab:blue"

            plt.scatter(index, pass_rate, color=point_color, s=55, zorder=3)
            plt.text(
                index,
                pass_rate + 0.15,
                f"{pass_rate:.1f}",
                ha="center",
                va="bottom",
                fontsize=TOTAL_PASS_RATE_LABEL_SIZE,
                color=point_color,
            )

    # Red ticks show the minimum acceptable pass rate for each aggregated test.
    for index, test_name in enumerate(test_names):
        plt.hlines(
            minimum_pass_rates[test_name],
            index - 0.28,
            index + 0.28,
            color="tab:red",
            linestyle="--",
            linewidth=1.2,
            label="Minimum pass rate" if index == 0 else None,
        )

    # Dotted line for the expected pass rate, based on alpha.
    plt.axhline(
        expected_pass_rate,
        color="tab:green",
        linestyle=":",
        linewidth=1.5,
        label=f"1 - alpha ({expected_pass_rate:.2f}%)",
    )

    plt.title("NIST tests - total pass rate per test")
    plt.xlabel("Statistical test")
    plt.ylabel("Passed bitstreams [%]")
    plt.ylim(y_min, y_max)
    plt.xticks(x_values, test_names, rotation=45, ha="right")
    plt.grid(axis="y", linestyle="--", alpha=0.4)
    plt.legend(loc="lower left")

    plt.tight_layout()
    plt.savefig(output_file, dpi=200)
    plt.close()


def main():
    # The bash script gives the paths to Python.
    # In this way, projectStructure.sh remains the only place where project paths are defined.
    # Example:
    # python3 scripts/utility_scripts/plot_NIST_results.py finalAnalysisReport.txt graph.png histograms summary.csv 100
    if len(sys.argv) != 6:
        print(
            "Usage: python3 plot_NIST_results.py "
            "<finalAnalysisReport.txt> <total_pass_plot.png> "
            "<uniformity_plot_folder> <uniformity_summary.csv> <number_of_streams>"
        )
        sys.exit(1)

    report_file = Path(sys.argv[1])
    total_pass_output_file = Path(sys.argv[2])
    uniformity_plot_folder = Path(sys.argv[3])
    uniformity_summary_file = Path(sys.argv[4])
    number_of_streams = int(sys.argv[5])

    nist_data = read_final_analysis_report(report_file)
    plot_total_pass_rate_by_test(nist_data, total_pass_output_file, number_of_streams)
    plot_uniformity_histograms_by_test(nist_data, uniformity_plot_folder, uniformity_summary_file, number_of_streams)

    print(f"Read records: {len(nist_data['records'])}")
    print(f"Saved graph: {total_pass_output_file}")
    print(f"Saved histograms: {uniformity_plot_folder}")
    print(f"Saved uniformity summary: {uniformity_summary_file}")


if __name__ == "__main__":
    main()
