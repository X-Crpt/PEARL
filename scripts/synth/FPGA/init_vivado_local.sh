#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# ==============================================================================================
# Local Vivado environment initialization.
# ----------------------------------------------------------------------------------------------
# Used as a drop-in replacement for the remote-server init script (SERVER_SCRIPT_SYNTH_FPGA_INIT,
# see projectStructure.sh) when FPGA synthesis is run directly on a machine that already has
# Vivado installed (see scripts/run_SYNTH_FPGA_LOCAL.sh). Override VIVADO_LOCAL_SETTINGS to point
# at a different Vivado install if needed.
# ==============================================================================================

VIVADO_LOCAL_SETTINGS="${VIVADO_LOCAL_SETTINGS:-/path/to/xilinx/Vivado/2024.2/settings64.sh}"

if [[ ! -f "$VIVADO_LOCAL_SETTINGS" ]]; then
	echo "ERROR: Vivado settings script not found: $VIVADO_LOCAL_SETTINGS" >&2
	echo "Set VIVADO_LOCAL_SETTINGS to the correct settings64.sh path." >&2
	return 1 2>/dev/null || exit 1
fi

source "$VIVADO_LOCAL_SETTINGS"
