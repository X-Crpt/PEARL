#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# ==============================================================================================
# Target: Execute ASIC synthesis directly on this machine (no remote server).
# ----------------------------------------------------------------------------------------------
# run_SYNTH_ASIC.sh assumes RTL/testbench/scripts must be rsync'd to a remote server that has
# Synopsys Design Compiler installed, then run over SSH (see run_ASIC_synth_server.sh). This
# machine already has Design Compiler at the default path the scripts expect
# (SERVER_SCRIPT_SYNTH_ASIC_INIT, see projectStructure.sh) and the crheepto_wip PDK symlinks
# resolve locally, so this script skips the rsync/SSH round-trip and calls the same server-side
# synthesis script directly against the local project tree.
#
# Usage: identical to run_SYNTH_ASIC.sh, e.g.:
#   ./scripts/run_SYNTH_ASIC_LOCAL.sh -module ctr_drbg -variant AES_CORE -param ENCRYPTION_CORE=1
# ==============================================================================================

set -e
set -u
set -o pipefail

PROJECT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")

exec "$PROJECT_ROOT/scripts/synth/ASIC/run_ASIC_synth_server.sh" "$@"
