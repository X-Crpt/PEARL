#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# ==============================================================================================
# Target: Execute FPGA synthesis directly on this machine (no remote server).
# ----------------------------------------------------------------------------------------------
# run_SYNTH_FPGA.sh assumes RTL/testbench/scripts must be rsync'd to a remote server that has
# Vivado installed, then run over SSH (see run_FPGA_synth_server.sh, run_FPGA_synth_server.tcl).
# This script skips the rsync/SSH round-trip and calls the same server-side synthesis script
# directly against the local project tree, for machines (like this one) that already have
# Vivado installed locally.
#
# Usage: identical to run_SYNTH_FPGA.sh, e.g.:
#   ./scripts/run_SYNTH_FPGA_LOCAL.sh -module ctr_drbg -variant AES_CORE -param ENCRYPTION_CORE=1
#
# Set VIVADO_LOCAL_SETTINGS to override the default Vivado install used
# (see scripts/synth/FPGA/init_vivado_local.sh).
# ==============================================================================================

set -e
set -u
set -o pipefail

PROJECT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

# Point the server-side script at a local Vivado environment-init script instead of the
# remote-only default (SERVER_SCRIPT_SYNTH_FPGA_INIT, see projectStructure.sh).
export SERVER_SCRIPT_SYNTH_FPGA_INIT="$PROJECT_ROOT/scripts/synth/FPGA/init_vivado_local.sh"

exec "$PROJECT_ROOT/scripts/synth/FPGA/run_FPGA_synth_server.sh" "$@"
