#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------
# Bash script flow:
# 1) Parse module and variant name from command line
# 2) Build VCD path inside sim/<module>/<variant>/logs
# 3) Run GTKWave on that VCD
# ==============================================================================================

set -e				# Fail if any command exits with an error
set -u				# Fail if an undefined variable is used
set -o pipefail		# Fail a pipeline if any command inside it fails

# ===============================================================================================
# ------------------------------ Parse all the Command Options ----------------------------------
# ===============================================================================================

# Variables set by command line options
MODULE_NAME="NOT_SET"
VARIANT_NAME="default"

while [[ $# -gt 0 ]]; do
	case "$1" in
		-module)
			if [[ -z "${2:-}" ]]; then
				echo "❌ -module option requires the name of the module (e.g., -module AES_128)"
				exit 1
			fi
			MODULE_NAME="$2"
			shift 2
			;;

		-variant)
			if [[ -z "${2:-}" ]]; then
				echo "❌ -variant option requires the variant name (e.g., -variant default)"
				exit 1
			fi
			VARIANT_NAME="$2"
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

# ===============================================================================================
# ------------------------- Prepare constants useful in the script ------------------------------
# ===============================================================================================

# Find the Project Root and define main folders inside the Project
PROJECT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")

source "${PROJECT_ROOT}/scripts/utility_scripts/projectStructure.sh"

if [[ ! -f "$VCD_FILE" ]]; then
	echo "❌ FAIL: VCD file not found at $VCD_FILE"
	exit 1
fi

echo "[${MODULE_NAME}/${VARIANT_NAME}] ▶ Opening GTKWave..."
gtkwave "$VCD_FILE"
