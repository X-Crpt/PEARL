#!/bin/bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

set -e				# Fail if any command exits with an error
set -u				# Fail if an undefined variable is used
set -o pipefail		# Fail a pipeline if any command inside it fails

SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
export PROJECT_ROOT="$(realpath "$SCRIPT_DIR/../../..")"

MODULE_NAME="NOT_SET"
VARIANT_NAME="default"
VARIANT_EXPLICIT=0
SYNTH_PARAMETER_OVERRIDE_ARGS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		-module)
			if [[ -z "${2:-}" ]]; then
				echo "ERROR: -module requires the name of the module to synthesize"
				exit 1
			fi
			MODULE_NAME="$2"
			shift 2
			;;

		-variant)
			if [[ -z "${2:-}" ]]; then
				echo "ERROR: -variant requires a variant name"
				exit 1
			fi
			VARIANT_NAME="$2"
			VARIANT_EXPLICIT=1
			shift 2
			;;

		-param)
			if [[ -z "${2:-}" || "$2" != *=* ]]; then
				echo "ERROR: -param requires NAME=VALUE"
				exit 1
			fi
			SYNTH_PARAMETER_OVERRIDE_ARGS+=("$2")
			shift 2
			;;

		-*)
			echo "ERROR: unknown option: $1"
			exit 1
			;;

		*)
			echo "ERROR: unexpected positional argument: $1"
			echo "Usage: $0 -module <module_name> [-param NAME=VALUE ...]"
			exit 1
			;;
	esac
done

if [[ "$MODULE_NAME" == "NOT_SET" ]]; then
	echo "ERROR: missing required option: -module"
	exit 1
fi

if [[ ${#SYNTH_PARAMETER_OVERRIDE_ARGS[@]} -gt 0 && "$VARIANT_EXPLICIT" -eq 0 ]]; then
	echo "ERROR: parameter overrides require -variant <name>, to avoid overwriting default results"
	exit 1
fi

# Print the Parameters Over-rides accepted
if [[ ${#SYNTH_PARAMETER_OVERRIDE_ARGS[@]} -gt 0 ]]; then
	echo "Using synthesis parameter overrides:"
	for param_override in "${SYNTH_PARAMETER_OVERRIDE_ARGS[@]}"; do
		echo "  - $param_override"
	done
fi

export MODULE_NAME
export VARIANT_NAME
export SYNTH_PARAMETER_OVERRIDES="${SYNTH_PARAMETER_OVERRIDE_ARGS[*]}"

# Include all the constants containing the position of folder/files/scripts in the project
source "${PROJECT_ROOT}/scripts/utility_scripts/projectStructure.sh"

# Include function Libraries
source "$BASH_LIB_GENERAL"

# Create directories for files generated during the synthesis process.
general_makeFolder_noDeletePreviuous	"$SYNTH_FPGA_NETLIST_FOLDER"
general_makeFolder_noDeletePreviuous	"$SYNTH_FPGA_REPORTS_FOLDER"
general_makeFolder_noDeletePreviuous	"$SYNTH_FPGA_LOGS_FOLDER"
general_makeFolder_deletePreviuous		"$SYNTH_FPGA_WORK_FOLDER"

echo "[$MODULE_NAME/$VARIANT_NAME] Running Vivado FPGA synthesis ..."

cd "$SYNTH_FPGA_WORK_FOLDER"

LOG_SYNTH_FPGA_REL=$(general_stripProjectRoot "$LOG_SYNTH_FPGA")
STDOUT_SYNTH_FPGA_REL=$(general_stripProjectRoot "$STDOUT_SYNTH_FPGA")

echo "Full synthesis log:"
echo "  $LOG_SYNTH_FPGA_REL"
echo "Vivado stdout log:"
echo "  $STDOUT_SYNTH_FPGA_REL"
echo "Follow live:"
echo "  tail -f <file_path>"

# Run the synthesis in batch mode: Vivado writes its detailed log files, stdin is closed to avoid hidden interactive
# prompts, and the heartbeat below keeps the main terminal alive without flooding it.
source $SERVER_SCRIPT_SYNTH_FPGA_INIT > /dev/null       ; # Initialize the eviroment for the Synopys syntesizer

vivado -mode batch \
	-source "$TCL_SCRIPT_SYNTH_FPGA" \
	-log "$LOG_SYNTH_FPGA" \
	-journal "$JOURNAL_SYNTH_FPGA" \
	> "$STDOUT_SYNTH_FPGA" 2>&1 < /dev/null &
set +u
synth_pid=$!
set -u
if [[ -z "$synth_pid" ]]; then
	echo "ERROR: Vivado did not start. Check logs:"
	echo "  $LOG_SYNTH_FPGA_REL"
	echo "  $STDOUT_SYNTH_FPGA_REL"
	exit 1
fi
last_log_size=0

while kill -0 "$synth_pid" 2>/dev/null; do
	if [[ -f "$LOG_SYNTH_FPGA" ]]; then
		current_log_size=$(wc -c < "$LOG_SYNTH_FPGA")
	else
		current_log_size=0
	fi

	if [[ "$current_log_size" -gt "$last_log_size" ]]; then
		echo "Vivado synthesis still running... log updated (${current_log_size} bytes, $(date '+%H:%M:%S'))"
	else
		echo "Vivado synthesis still running... log unchanged (${current_log_size} bytes, $(date '+%H:%M:%S'))"
	fi

	last_log_size="$current_log_size"
	sleep 30
done

if wait "$synth_pid"; then
	echo "Vivado synthesis completed."
else
	synth_status=$?
	echo "Vivado synthesis failed with exit code $synth_status. Check log:"
	echo "  $LOG_SYNTH_FPGA_REL"
	echo "  $STDOUT_SYNTH_FPGA_REL"
	exit "$synth_status"
fi
