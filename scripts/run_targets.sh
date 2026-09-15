#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

set -e
set -u
set -o pipefail

PROJECT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

source "${PROJECT_ROOT}/scripts/utility_scripts/projectStructure.sh"
source "$BASH_LIB_JSON"
source "$BASH_LIB_GENERAL"
source "$BASH_LIB_PRINT"

CONFIG_FILE="$CONFIG_TARGETS"

SELECTED_MODULE=""
SELECTED_VARIANT=""
FLOWS=()
NUM_PATTERNS=10
NIST_STREAM_LENGTH=100000
NIST_STREAM_NUM=10
NIST_PLOT_ONLY=0
KEEP_GOING=0

usage() {
	cat <<EOF
Usage: $0 [options]

Options:
  -module <name>          Run only this module. Can be used only once.
  -variant <name>         Run only this variant. Requires -module.
  -flow <name>            Select a flow. Can be repeated.
                          Valid flows: sim, nist, synth_asic, synth_fpga.
  -config <path>          JSON target list. Default: scripts/config/targets.json.
  -num_patterns <num>     Number of simulation patterns. Default: $NUM_PATTERNS.
  -stream_length <num>    NIST stream length. Default: $NIST_STREAM_LENGTH.
  -stream_num <num>       NIST number of streams. Default: $NIST_STREAM_NUM.
  -nist_plot_only         Regenerate NIST plots from saved per-variant finalAnalysisReport.txt files.
  -keep_going             Continue after a failed step.
  -h, -help, --help       Show this help.
EOF
}

add_flow() {
	local flow="$1"

	case "$flow" in
		sim|nist|synth_asic|synth_fpga)
			FLOWS+=("$flow")
			;;
		*)
			echo "ERROR: unknown flow: $flow" >&2
			exit 1
			;;
	esac
}

flow_is_selected() {
	local requested_flow="$1"
	local flow

	for flow in "${FLOWS[@]}"; do
		if [[ "$flow" == "$requested_flow" ]]; then
			return 0
		fi
	done

	return 1
}

load_variant_params() {
	local __dest="$1"
	local module_name="$2"
	local variant_name="$3"
	local jq_filter=".modules[\"$module_name\"].variants[\"$variant_name\"].params"
	local param

	while IFS= read -r param; do
		eval "$__dest+=(\"\$param\")"
	done < <(jq -r "$jq_filter | to_entries[]? | \"\(.key)=\(.value)\"" "$CONFIG_FILE")
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-module)
			if [[ -n "$SELECTED_MODULE" ]]; then
				echo "ERROR: -module can be used only once" >&2
				exit 1
			fi
			if [[ -z "${2:-}" ]]; then
				echo "ERROR: -module requires a module name" >&2
				exit 1
			fi
			SELECTED_MODULE="$2"
			shift 2
			;;

		-variant)
			if [[ -z "${2:-}" ]]; then
				echo "ERROR: -variant requires a variant name" >&2
				exit 1
			fi
			SELECTED_VARIANT="$2"
			shift 2
			;;

		-flow)
			if [[ -z "${2:-}" ]]; then
				echo "ERROR: -flow requires one of: sim, nist, synth_asic, synth_fpga" >&2
				exit 1
			fi
			add_flow "$2"
			shift 2
			;;

		-config)
			if [[ -z "${2:-}" ]]; then
				echo "ERROR: -config requires a JSON file path" >&2
				exit 1
			fi
			CONFIG_FILE="$2"
			shift 2
			;;

		-num_patterns)
			NUM_PATTERNS="$2"
			shift 2
			;;

		-stream_length)
			NIST_STREAM_LENGTH="$2"
			shift 2
			;;

		-stream_num)
			NIST_STREAM_NUM="$2"
			shift 2
			;;

		-nist_plot_only)
			NIST_PLOT_ONLY=1
			shift
			;;

		-keep_going)
			KEEP_GOING=1
			shift
			;;

		-h|-help|--help)
			usage
			exit 0
			;;

		-*)
			echo "ERROR: unknown option: $1" >&2
			usage
			exit 1
			;;

		*)
			echo "ERROR: unexpected argument: $1" >&2
			usage
			exit 1
			;;
	esac
done

if [[ ${#FLOWS[@]} -eq 0 ]]; then
	if [[ "$NIST_PLOT_ONLY" -eq 1 ]]; then
		FLOWS=(nist)
	else
		FLOWS=(sim nist synth_asic synth_fpga)
	fi
fi

if [[ "$NIST_PLOT_ONLY" -eq 1 ]]; then
	for flow in "${FLOWS[@]}"; do
		if [[ "$flow" != "nist" ]]; then
			echo "ERROR: -nist_plot_only can be used only with the nist flow" >&2
			exit 1
		fi
	done
fi

if [[ -n "$SELECTED_VARIANT" && -z "$SELECTED_MODULE" ]]; then
	echo "ERROR: -variant can be used only together with -module" >&2
	exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
	echo "ERROR: config file not found: $CONFIG_FILE" >&2
	exit 1
fi

MODULES=()
if [[ -n "$SELECTED_MODULE" ]]; then
	if ! JSON_objectHasKey "$CONFIG_FILE" ".modules" "$SELECTED_MODULE"; then
		echo "ERROR: module not found in config: $SELECTED_MODULE" >&2
		exit 1
	fi
	MODULES=("$SELECTED_MODULE")
else
	JSON_loadObjectKeys MODULES "$CONFIG_FILE" ".modules"
fi

FAILED_STEPS=()
NIST_COMPARISON_ARGS=()

report_missing_prerequisite() {
	local reason="$4"

	echo "❌ Missing prerequisite: $reason"
	return 1
}

run_step() {
	local module_name="$1"
	local variant_name="$2"
	local flow="$3"
	shift 3

	print_flow_title "$flow"

	set +e
	"$@"
	local status=$?
	set -e

	if [[ $status -eq 0 ]]; then
		print_flow_footer "✅ Flow completed: $flow"
		return 0
	fi

	print_flow_footer "❌ Flow failed: $flow (exit code $status)"
	FAILED_STEPS+=("$module_name:$variant_name:$flow:$status")

	if [[ "$KEEP_GOING" -eq 0 ]]; then
		exit "$status"
	fi

	return 0
}

run_variant_flow() {
	local module_name="$1"
	local variant_name="$2"
	local flow="$3"
	shift 3
	local params=("$@")
	local param_args=()
	local nist_mode_args=()
	local param

	for param in "${params[@]}"; do
		param_args+=(-param "$param")
	done

	if [[ "$NIST_PLOT_ONLY" -eq 1 ]]; then
		nist_mode_args+=(-plot_only)
	fi

	local sim_prj="$PRJ_FOLDER/${module_name}_SIM.prj"
	local synth_asic_prj="$PRJ_FOLDER/${module_name}_SYNTH_ASIC.prj"
	local synth_fpga_prj="$PRJ_FOLDER/${module_name}_SYNTH_FPGA.prj"
	local golden_sim="$GOLDEN_MODEL_FOLDER/${module_name}/main_SIM.cpp"
	local golden_nist="$GOLDEN_MODEL_FOLDER/${module_name}/main_NIST.cpp"

	case "$flow" in
		sim)
			if [[ -f "$sim_prj" && -f "$golden_sim" ]]; then
				run_step "$module_name" "$variant_name" "$flow" \
					"$SCRIPT_RUN_SIM" \
					-module "$module_name" \
					-variant "$variant_name" \
					-num_patterns "$NUM_PATTERNS" \
					"${param_args[@]}"
			else
				run_step "$module_name" "$variant_name" "$flow" \
					report_missing_prerequisite \
					"$module_name" "$variant_name" "$flow" \
					"${module_name}_SIM.prj or main_SIM.cpp"
			fi
			;;

		nist)
			if [[ "$NIST_PLOT_ONLY" -eq 1 || -f "$golden_nist" ]]; then
				run_step "$module_name" "$variant_name" "$flow" \
					"$SCRIPT_RUN_NIST" \
					-module "$module_name" \
					-variant "$variant_name" \
					-stream_length "$NIST_STREAM_LENGTH" \
					-stream_num "$NIST_STREAM_NUM" \
					"${nist_mode_args[@]}" \
					"${param_args[@]}"
			else
				run_step "$module_name" "$variant_name" "$flow" \
					report_missing_prerequisite \
					"$module_name" "$variant_name" "$flow" \
					"main_NIST.cpp"
			fi
			;;

		synth_asic)
			if [[ -f "$synth_asic_prj" ]]; then
				run_step "$module_name" "$variant_name" "$flow" \
					"$SCRIPT_RUN_SYNTH_ASIC" \
					-module "$module_name" \
					-variant "$variant_name" \
					"${param_args[@]}"
			else
				run_step "$module_name" "$variant_name" "$flow" \
					report_missing_prerequisite \
					"$module_name" "$variant_name" "$flow" \
					"${module_name}_SYNTH_ASIC.prj"
			fi
			;;

		synth_fpga)
			if [[ -f "$synth_fpga_prj" ]]; then
				run_step "$module_name" "$variant_name" "$flow" \
					"$SCRIPT_RUN_SYNTH_FPGA" \
					-module "$module_name" \
					-variant "$variant_name" \
					"${param_args[@]}"
			else
				run_step "$module_name" "$variant_name" "$flow" \
					report_missing_prerequisite \
					"$module_name" "$variant_name" "$flow" \
					"${module_name}_SYNTH_FPGA.prj"
			fi
			;;
	esac
}

for module_name in "${MODULES[@]}"; do
	VARIANTS=()

	if [[ -n "$SELECTED_VARIANT" ]]; then
		if ! JSON_objectHasKey "$CONFIG_FILE" ".modules[\"$module_name\"].variants" "$SELECTED_VARIANT"; then
			echo "ERROR: variant not found for module $module_name: $SELECTED_VARIANT" >&2
			exit 1
		fi
		VARIANTS=("$SELECTED_VARIANT")
	else
		JSON_loadObjectKeys VARIANTS "$CONFIG_FILE" ".modules[\"$module_name\"].variants"
	fi

	for variant_name in "${VARIANTS[@]}"; do
		PARAMS=()
		load_variant_params PARAMS "$module_name" "$variant_name"

		echo
		if [[ ${#PARAMS[@]} -gt 0 ]]; then
			params_text="${PARAMS[*]}"
		else
			params_text="<none>"
		fi
		print_module_header "$module_name" "$variant_name" "$params_text" "${FLOWS[*]}"

		if [[ -z "$SELECTED_MODULE" ]] && flow_is_selected "nist"; then
			NIST_COMPARISON_ARGS+=(-module "$module_name")
			if [[ "$variant_name" != "default" ]]; then
				NIST_COMPARISON_ARGS+=(-variant "$variant_name")
			fi
		fi

		for flow in "${FLOWS[@]}"; do
			run_variant_flow "$module_name" "$variant_name" "$flow" "${PARAMS[@]}"
		done
	done
done

if [[ ${#FAILED_STEPS[@]} -eq 0 ]] && flow_is_selected "synth_asic"; then
	echo
	print_flow_title "asic_pareto_plot"

	set +e
	"$SCRIPT_PLOT_SYNTH_ASIC_PARETO"
	plot_status=$?
	set -e

	if [[ $plot_status -eq 0 ]]; then
		print_flow_footer "✅ ASIC Pareto plot updated"
	else
		print_flow_footer "❌ ASIC Pareto plot failed (exit code $plot_status)"
		FAILED_STEPS+=("plot:asic_pareto:plot:$plot_status")
	fi
fi

if [[ ${#FAILED_STEPS[@]} -eq 0 ]] && flow_is_selected "synth_fpga"; then
	echo
	print_flow_title "fpga_pareto_plot"

	set +e
	"$SCRIPT_PLOT_SYNTH_FPGA_PARETO"
	plot_status=$?
	set -e

	if [[ $plot_status -eq 0 ]]; then
		print_flow_footer "✅ FPGA Pareto plot updated"
	else
		print_flow_footer "❌ FPGA Pareto plot failed (exit code $plot_status)"
		FAILED_STEPS+=("plot:fpga_pareto:plot:$plot_status")
	fi
fi

if [[ ${#FAILED_STEPS[@]} -eq 0 ]] && [[ -z "$SELECTED_MODULE" ]] && [[ ${#NIST_COMPARISON_ARGS[@]} -ge 4 ]] && flow_is_selected "nist"; then
	echo
	print_flow_title "nist_comparison_plot"

	set +e
	"$SCRIPT_NIST_compare" \
		"${NIST_COMPARISON_ARGS[@]}" \
		-stream_num "$NIST_STREAM_NUM" \
		-include_averages
	plot_status=$?
	set -e

	if [[ $plot_status -eq 0 ]]; then
		print_flow_footer "✅ NIST comparison plots updated"
	else
		print_flow_footer "❌ NIST comparison plots failed (exit code $plot_status)"
		FAILED_STEPS+=("plot:nist_comparison:plot:$plot_status")
	fi
fi

echo
echo "============================================================================================"
echo "RUN TARGETS SUMMARY"
echo "============================================================================================"
echo "Targets: $(general_stripProjectRoot "$CONFIG_FILE")"
echo "Flows: ${FLOWS[*]}"
echo "Failed: ${#FAILED_STEPS[@]}"
for failed_step in "${FAILED_STEPS[@]}"; do
	echo "  ❌ $failed_step"
done

if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
	exit 1
fi

echo "✅ All requested steps completed."
