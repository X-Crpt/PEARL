#!/bin/bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

set -e				# Fail if any command exits with an error
set -u				# Fail if an undefined variable is used
set -o pipefail		# Fail a pipeline if any command inside it fails

# Find the Project Root and define main folders inside the Project
PROJECT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

# Variables set by command line options
MODULE_NAME="NOT_SET"
VARIANT_NAME="default"
VARIANT_EXPLICIT=0
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

if [[ "$MODULE_NAME" == "NOT_SET" ]]; then
	echo "❌ Missing required option: -module"
	exit 1
fi

if [[ ${#PARAM_OVERRIDES[@]} -gt 0 && "$VARIANT_EXPLICIT" -eq 0 ]]; then
	echo "❌ Parameter overrides require -variant <name>, to avoid overwriting default results"
	exit 1
fi

# Print the Parameters Over-rides accepted
if [[ ${#PARAM_OVERRIDES[@]} -gt 0 ]]; then
	echo "Synthesis parameter overrides:"
	for param_override in "${PARAM_OVERRIDES[@]}"; do
		echo "  - $param_override"
	done
fi


source "${PROJECT_ROOT}/scripts/utility_scripts/projectStructure.sh"

# Include function Libraries
source "$BASH_LIB_GENERAL"
source "$BASH_LIB_SERVER"
source "$BASH_LIB_PRINT"

# Set up the server with all the necessary files
print_phase "Send Data To Server"
server_shareFolder_PCtoServer "$RTL_FOLDER"
if [[ -f "$PRJ_FILE_SYNTH_ASIC" ]] && grep -q "$KECCAK_RTL_SERVER_REL/" "$PRJ_FILE_SYNTH_ASIC"; then
	server_shareFolder_PCtoServer "$KECCAK_RTL_FOLDER" "$KECCAK_RTL_SERVER_REL"
fi
server_shareFolder_PCtoServer "$TB_FOLDER"
server_shareFolder_PCtoServer "$SCRIPT_FOLDER"
server_shareFolder_PCtoServer "$SYNTH_ASIC_SCRIPTS_FOLDER"
server_shareFolder_PCtoServer "$BASH_LIB_FOLDER"
server_shareFolder_PCtoServer "$PRJ_FOLDER"
server_shareFolder_PCtoServer "$CRHEEPTO_WIP_FOLDER/hw/asic/symlinks" "crheepto_wip/hw/asic/symlinks"

# Synthesis process using "compile"
SERVER_SYNTH_ARGS=(-module "$MODULE_NAME" -variant "$VARIANT_NAME")
for param_override in "${PARAM_OVERRIDES[@]}"; do
	SERVER_SYNTH_ARGS+=(-param "$param_override")
done
set +e
server_executeScript "$SCRIPT_RUN_SYNTH_ASIC_SERVER" "${SERVER_SYNTH_ARGS[@]}"
synth_status=$?
set -e

# Retrive only the current module ASIC synthesis results from the server.
ASIC_RESULT_REL=$(general_stripProjectRoot "$SYNTH_ASIC_RESULT_FOLDER")
print_phase "Receive Results From Server"
echo "Results: $ASIC_RESULT_REL"
server_shareFolder_ServerToPC "$SYNTH_ASIC_RESULT_FOLDER"

if [[ "$synth_status" -ne 0 ]]; then
	exit "$synth_status"
fi
