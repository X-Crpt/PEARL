#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------
# Bash script flow:
# 1) Compile and run Golden Model
# 2) Run Verilator simulation using .prj filelist (including SystemVerilog TB)
# ==============================================================================================

set -e				# Fail if any command exits with an error
set -u				# Fail if an undefined variable is used
set -o pipefail		# Fail a pipeline if any command inside it fails

# Find the Project Root and define main folders inside the Project
PROJECT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

# ===============================================================================================
# ------------------------------ Parse all the Command Options ----------------------------------
# ===============================================================================================

# Variables set by command line options
MODULE_NAME="NOT_SET"
VARIANT_NAME="default"
VARIANT_EXPLICIT=0
NUM_PATTERNS=10
PARAM_OVERRIDES=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		-module)
			if [[ -z "${2:-}" ]]; then
				echo "❌ -module option requires the name of the module to be simulated (e.g., -module AES_128)"
				exit 1
			fi
			MODULE_NAME="$2"
			shift 2
			;;

		-num_patterns)
			if [[ -z "${2:-}" ]]; then
				echo "❌ -num_patterns option requires a numeric value (e.g., -num_patterns 20)"
				exit 1
			fi
			NUM_PATTERNS="$2"
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

		-param)
			if [[ -z "${2:-}" || "$2" != *=* ]]; then
				echo "❌ -param requires NAME=VALUE"
				exit 1
			fi

			PARAM_OVERRIDES+=("$2")
			shift 2
			;;

		-*)
			echo "❌ Unknown option: $1"
			exit 1
			;;
	esac
done

# Check if all the mandatory command line parameters were actually shared
if [[ "$MODULE_NAME" == "NOT_SET" ]]; then
	echo "❌ Missing required option: -module"
	exit 1
fi

if [[ ${#PARAM_OVERRIDES[@]} -gt 0 && "$VARIANT_EXPLICIT" -eq 0 ]]; then
	echo "❌ Parameter overrides require -variant <name>, to avoid overwriting default results"
	exit 1
fi

# Prepare the input parameters over-rides in the format ready to be shared to the 
# Golden Model and Verilator
GOLDEN_PARAM_ARGS=()
VERILATOR_PARAM_ARGS=()
for param_override in "${PARAM_OVERRIDES[@]}"; do
	GOLDEN_PARAM_ARGS+=("+$param_override")
	VERILATOR_PARAM_ARGS+=("-G$param_override")
done

# Define all the paths and files for the current project and the MODULE_NAME requested
source "${PROJECT_ROOT}/scripts/utility_scripts/projectStructure.sh"
source "$BASH_LIB_PRINT"

VERILATOR_CXX=""

# Prepare all Folders needed for the Simulation process (basically make sure they exist)
mkdir -p "$SIM_LOG_FOLDER" "$SIM_REPORT_FOLDER" "$BUILD_FOLDER" "$EXEC_FOLDER" "$VECTOR_FOLDER"
: > "$SIM_SCRIPT_LOG"				# Clear log file at the beginning of the script execution
exec > >(tee -a "$SIM_SCRIPT_LOG") 2>&1	# Redirect all output (stdout and stderr) to the log file while maintainig it on the terminal

if [[ ${#PARAM_OVERRIDES[@]} -gt 0 ]]; then
	echo "Simulation parameter overrides:"
	for param_override in "${PARAM_OVERRIDES[@]}"; do
		echo "  - $param_override"
	done
fi

# ===============================================================================================
# ----------------------------------- Execute the Golden Model ----------------------------------
# ===============================================================================================
print_phase "Golden Model Build"
# Check that a source file exists for the GoldenModel
if [[ ! -f "$GOLDEN_SIM_SRC" ]]; then
	echo "❌ Golden Model source not found: $GOLDEN_SIM_SRC"
	exit 1
fi

# Check if the Golden Model Makefile exists
if [[ ! -f "$GOLDEN_MAKEFILE" ]]; then
	echo "❌ Golden Model Makefile not found: $GOLDEN_MAKEFILE"
	exit 1
fi

# Compile the Golden Model using its Makefile and print the compilation terminal dump in the Goldenmodel log file
if ! {
	make -C "$GOLDEN_FOLDER" \
		MAIN="$GOLDEN_SIM_MAIN" \
		MODULE_NAME="$MODULE_NAME" \
		TARGET_DIR="$EXEC_FOLDER"
} > "$SIM_GOLDENMODEL_LOG" 2>&1; then
	echo "❌ Golden Model compilation failed"
	echo "Log: $SIM_GOLDENMODEL_LOG"
	print_phase "Last log lines"
	tail -n 80 "$SIM_GOLDENMODEL_LOG"
	exit 1
fi
echo "Golden Model build completed"


print_phase "Golden Model Run"
# Execute the Golden Model and print the terminal dump in the Goldenmodel log file
"$GOLDEN_EXE" "$NUM_PATTERNS" "$INPUT_VECTOR_FILE" "$OUTPUT_VECTOR_FILE" "${GOLDEN_PARAM_ARGS[@]}"
status=$?
if [[ $status -ne 0 ]]; then
	echo "❌ Golden Model execution failed"
	exit 1
fi
echo "Golden Model run completed"
echo ""


# ==============================================================================================
# ------------------------------- Simulate the HDL (using Verilator) ---------------------------
# ==============================================================================================
# Check if the .prj file exists (contains the list of all SystemVerilog files needed for the simulation)
if [[ ! -f "$PRJ_FILE_SIM" ]]; then
	echo "❌ PRJ file not found: $PRJ_FILE_SIM"
	exit 1
fi

# Build absolute-path filelist from .prj and save it inside build/
: > "$TMP_ABS_PRJ_FILE"

# Add the project root to all the paths in the Project File
# Project file does not contain absolute paths for ease of sharing this script/project
while IFS= read -r line || [[ -n "$line" ]]; do
	# Ignore empty lines (or lines with only spaces/tabs)
	if [[ -z "${line//[[:space:]]/}" ]]; then
		continue
	fi

	echo "$PROJECT_ROOT/$line" >> "$TMP_ABS_PRJ_FILE"
done < "$PRJ_FILE_SIM"

if [[ ! -f "$ABS_PRJ_FILE" ]] || ! cmp -s "$TMP_ABS_PRJ_FILE" "$ABS_PRJ_FILE"; then
	mv "$TMP_ABS_PRJ_FILE" "$ABS_PRJ_FILE"
else
	rm -f "$TMP_ABS_PRJ_FILE"
fi


print_phase "Verilator Build"
cd "$PROJECT_ROOT"
CXX="ccache g++" 
if ! {
	verilator -Wall --timing --trace --binary --build \
		-Wno-TIMESCALEMOD \
		-Wno-UNUSEDPARAM \
		-Wno-UNUSEDSIGNAL \
		-Wno-DECLFILENAME \
		-Wno-SYNCASYNCNET \
		--output-split 2000 \
		-j 0 \
		--top-module "TB_${MODULE_NAME}" \
		-Mdir "$BUILD_FOLDER" \
		-o "$SIM_EXE_NAME" \
		"${VERILATOR_PARAM_ARGS[@]}" \
		-f "$ABS_PRJ_FILE"
} > "$SIM_VERILATOR_LOG" 2>&1; then
	echo "❌ Verilator build failed"
	echo "Log: $SIM_VERILATOR_LOG"
	print_phase "Last log lines"
	tail -n 120 "$SIM_VERILATOR_LOG"
	exit 1
fi
echo "Verilator build completed"

# Move the Verilator executable to the executables folder
cp -f "$SIM_EXE_PATH" "$EXEC_FOLDER/"

# Run the Verilator simulation executable 
print_phase "Verilator Run"
"$SIM_EXE_PATH"	"$NUM_PATTERNS" \
				"+INPUT_VECT_FILE=$INPUT_VECTOR_FILE" \
				"+GOLD_VECT_FILE=$OUTPUT_VECTOR_FILE" \
				"+HDL_VECT_FILE=$HDL_OUTPUT_FILE" \
				"+PERF_FILE=$SIM_PERFORMANCE_FILE" \
				"+VCD_FILE=$VCD_FILE"
status=$?
if [[ $status -ne 0 ]]; then
	echo "❌ Verilator returned status: $status"
	exit 1
fi
