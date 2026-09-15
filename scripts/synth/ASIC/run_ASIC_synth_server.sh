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

echo "⏳ [$MODULE_NAME/$VARIANT_NAME] Running Design Vision (ASIC) Synthesis on Server..."


# Create Directories for all files generated during the Synthesis Process
general_makeFolder_noDeletePreviuous	"$SYNTH_ASIC_NETLIST_FOLDER"	; # working folder used directly by Design Vision to save files
general_makeFolder_noDeletePreviuous	"$SYNTH_ASIC_REPORT_FOLDER"		; # working folder used directly by Design Vision to save files
general_makeFolder_noDeletePreviuous	"$SYNTH_ASIC_LOG_FOLDER"		; # Final folders where the generated files will be permanently stored
general_makeFolder_deletePreviuous		"$SYNTH_ASIC_WORK_FOLDER"		; # Create a new Work folder for the Synthesis process

# Run the Synthesis process
cd "$SYNTH_ASIC_WORK_FOLDER"	
cp "$DC_SETUP_SYNTH_ASIC" "$SYNTH_ASIC_WORK_FOLDER"
export LM_LICENSE_FILE="${LM_LICENSE_FILE:-}"           ; # If the variable containing the License File does not exit, create an empty one (if it exists, does not modify it)
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"           ; # If the variable containing the Library does not exit, create an empty one (if it exists, does not modify it)
source $SERVER_SCRIPT_SYNTH_ASIC_INIT > /dev/null       ; # Initialize the eviroment for the Synopys syntesizer

# Print the messages to follow live the advancement of the Synthesis Process
LOG_SYNTH_ASIC_REL=$(general_stripProjectRoot "$LOG_SYNTH_ASIC")
echo "Full synthesis log:"
echo "  $LOG_SYNTH_ASIC_REL"
echo "Follow live with command: tail -f <file_path>"

# Run the synthesis in batch mode: all tool output goes to the log, stdin is closed to avoid hidden interactive prompts,
# and the heartbeat below keeps the main terminal alive without flooding it.
dc_shell-xg-t -f "$TCL_SCRIPT_SYNTH_ASIC" > "$LOG_SYNTH_ASIC" 2>&1 < /dev/null &
synth_pid=$!
if [[ -z "$synth_pid" ]]; then
	echo "ERROR: Design Vision did not start. Check log:"
	echo "  $LOG_SYNTH_ASIC_REL"
	exit 1
fi
last_log_size=0

while kill -0 "$synth_pid" 2>/dev/null; do
	current_log_size=$(wc -c < "$LOG_SYNTH_ASIC" 2>/dev/null || echo 0)

	if [[ "$current_log_size" -gt "$last_log_size" ]]; then
		echo "ASIC synth. running... log updated (${current_log_size} bytes, $(date '+%H:%M:%S'))"
	else
		echo "ASIC synth. running... log unchanged (${current_log_size} bytes, $(date '+%H:%M:%S'))"
	fi

	last_log_size="$current_log_size"
	sleep 30
done

if wait "$synth_pid"; then
	echo "ASIC synth. completed."
else
	synth_status=$?
	echo "ASIC synth. failed with exit code $synth_status. Check log:"
	echo "  $LOG_SYNTH_ASIC_REL"
	exit "$synth_status"
fi

if grep -q "^Error:" "$LOG_SYNTH_ASIC"; then
	echo "ASIC synth. completed with errors in the log. Check log:"
	echo "  $LOG_SYNTH_ASIC_REL"
	echo "Last errors:"
	grep "^Error:" "$LOG_SYNTH_ASIC" | tail -n 10
	exit 1
fi

# Cleanup all the un-necessary files generated by the Design Vision Synthesis process
rm -r -f $SYNTH_ASIC_WORK_FOLDER
