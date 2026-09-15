#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

set -e
set -u
set -o pipefail

# ===============================================================================================
# ------------------------------ Parse all the Command Options ----------------------------------
# ===============================================================================================

MODULE_NAME="NOT_SET"
VARIANT_NAME="default"
VARIANT_EXPLICIT=0
NIST_streamLength=100000
NIST_numberStreams=10
PLOT_ONLY=0
PARAM_OVERRIDES=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		-module)
			MODULE_NAME="$2"
			shift 2
			;;

		-variant)
			if [[ -z "${2:-}" ]]; then
				echo "❌ -variant option requires a variant name (e.g., -variant default)"
				exit 1
			fi
			VARIANT_NAME="$2"
			VARIANT_EXPLICIT=1
			shift 2
			;;

		-stream_length)
			NIST_streamLength="$2"
			shift 2
			;;

		-stream_num)
			NIST_numberStreams="$2"
			shift 2
			;;

		-plot_only)
			PLOT_ONLY=1
			shift
			;;

		-param)
			if [[ -z "${2:-}" || "$2" != *=* ]]; then
				echo "❌ -param requires NAME=VALUE"
				exit 1
			fi

			PARAM_OVERRIDES+=("$2")
			shift 2
			;;

		-*)
			echo "Unknown option: $1"
			exit 1
			;;
	esac
done

if [[ "$MODULE_NAME" == "NOT_SET" ]]; then
	echo "Missing required option: -module"
	exit 1
fi

if [[ ${#PARAM_OVERRIDES[@]} -gt 0 && "$VARIANT_EXPLICIT" -eq 0 ]]; then
	echo "❌ Parameter overrides require -variant <name>, to avoid overwriting default results"
	exit 1
fi

GOLDEN_PARAM_ARGS=()
for param_override in "${PARAM_OVERRIDES[@]}"; do
	GOLDEN_PARAM_ARGS+=("+$param_override")
done

# ===============================================================================================
# ------------------------- Prepare constants useful in the script ------------------------------
# ===============================================================================================

PROJECT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "${PROJECT_ROOT}/scripts/utility_scripts/projectStructure.sh"
source "$BASH_LIB_PRINT"

if [[ ${#PARAM_OVERRIDES[@]} -gt 0 ]]; then
	echo "NIST parameter overrides:"
	for param_override in "${PARAM_OVERRIDES[@]}"; do
		echo "  - $param_override"
	done
fi

NIST_bitsRequested=$((NIST_streamLength * NIST_numberStreams))
NIST_GOLDEN_EXE="$NIST_execFolder/goldenModel_NIST_${MODULE_NAME}"
NIST_variantAnalysisReport="$NIST_testFolder/finalAnalysisReport.txt"

mkdir -p "$NIST_testFolder" "$NIST_plotFolder" "$NIST_logFolder" "$NIST_execFolder"

if [[ "$PLOT_ONLY" -eq 0 ]]; then
	# ===============================================================================================
	# ----------------------------------- Execute the Golden Model ----------------------------------
	# ===============================================================================================
	print_phase "Golden Model Build"
	if [[ ! -f "$GOLDEN_NIST_SRC" ]]; then
		echo "❌ NIST Golden Model source not found: $GOLDEN_NIST_SRC"
		exit 1
	fi

	if [[ ! -f "$GOLDEN_MAKEFILE" ]]; then
		echo "❌ Golden Model Makefile not found: $GOLDEN_MAKEFILE"
		exit 1
	fi

	make -C "$GOLDEN_FOLDER" \
		MODULE_NAME="$MODULE_NAME" \
		TARGET_DIR="$NIST_execFolder" \
		TARGET_NAME="goldenModel_NIST_${MODULE_NAME}" \
		MAIN="$GOLDEN_NIST_MAIN" \
		> "$NIST_goldenModelLog" 2>&1
	echo "Golden Model build completed"
	print_project_log_path "$NIST_goldenModelLog"

	print_phase "Golden Model Run"
	"$NIST_GOLDEN_EXE" "$NIST_bitsRequested" "$NIST_inputFile" "${GOLDEN_PARAM_ARGS[@]}"
	echo "Golden Model run completed"
	echo ""

	# ===============================================================================================
	# ----------------------------------- Execute the NIST Tests ------------------------------------
	# ===============================================================================================
	print_phase "NIST Config File"
	printf "0\n%s\n1\n0\n%s\n0\n" "$NIST_inputFile" "$NIST_numberStreams" > "$NIST_testConfig"
	echo "NIST config file created"

	print_phase "NIST Build"
	{
		"$SCRIPT_NIST_setup"
		make -C "$NIST_stsFolder"
	} > "$NIST_buildLog" 2>&1
	echo "NIST build completed"
	print_project_log_path "$NIST_buildLog"

	print_phase "NIST Run"
	cd "$NIST_stsFolder"
	set +e
	"$SCRIPT_NIST_runTest" "$NIST_streamLength" < "$NIST_testConfig" > "$NIST_runLog" 2>&1
	status=$?
	set -e
	if [[ $status -ne 0 && $status -ne 1 ]]; then
		echo "❌ NIST execution failed"
		print_project_log_path "$NIST_runLog"
		print_phase "Last log lines"
		tail -n 120 "$NIST_runLog"
		exit 1
	fi
	echo "NIST tests completed"
	print_project_log_path "$NIST_runLog"

	cp "$NIST_finalAnalysisReport" "$NIST_variantAnalysisReport"
	echo "NIST final analysis report saved"
	print_project_log_path "$NIST_variantAnalysisReport"
else
	print_phase "NIST Plot Only"
	if [[ ! -f "$NIST_variantAnalysisReport" ]]; then
		echo "❌ Plot-only mode requires the variant report:"
		print_project_log_path "$NIST_variantAnalysisReport"
		echo "Run the full NIST flow once for this module/variant so the report is saved."
		exit 1
	fi
	echo "Using saved NIST final analysis report"
	print_project_log_path "$NIST_variantAnalysisReport"
fi

# ===============================================================================================
# ---------------------------------- Generate the NIST Plots ------------------------------------
# ===============================================================================================

print_phase "NIST Plots"
MPLCONFIGDIR="$NIST_plotFolder/matplotlib" python3 "$SCRIPT_NIST_plotResults" \
	"$NIST_variantAnalysisReport" \
	"$NIST_totalPassRatePlot" \
	"$NIST_uniformityPlotFolder" \
	"$NIST_uniformitySummaryFile" \
	"$NIST_numberStreams" \
	> "$NIST_plotLog" 2>&1
echo "NIST plots generated"
print_project_log_path "$NIST_plotLog"

python3 "$SCRIPT_NIST_summarizeResults" \
	"$NIST_variantAnalysisReport" \
	"$NIST_passRateSummaryFile" \
	| tee -a "$NIST_plotLog"
