#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# ==============================================================================================
# ASIC standard-cell / pad / memory library configuration -- ADD YOUR LIBRARY HERE
# ----------------------------------------------------------------------------------------------
# By default, ASIC synthesis (scripts/run_SYNTH_ASIC.sh / run_SYNTH_ASIC_LOCAL.sh) targets this
# repository's own reference PDK setup: the private crheepto_wip submodule, wrapping a
# proprietary foundry library. That default will not work outside the original lab, since it
# needs both access to that private submodule and a license for that specific PDK.
#
# To synthesize against your OWN standard-cell library instead:
#
#   1. Copy this file to scripts/config/asic_lib.local.sh (that exact path is git-ignored, so
#      your local paths/license details never get committed):
#
#        cp scripts/config/asic_lib.example.sh scripts/config/asic_lib.local.sh
#
#   2. Edit the copy: point the three LIB_SYNTH_ASIC_* variables below at the directories that
#      hold your Synopsys-readable (.db, e.g. compiled from .lib with Library Compiler)
#      standard-cell, I/O pad, and memory/macro libraries.
#
#   3. If your library files are not named like this repository's reference PDK, also override
#      the three *_GLOB patterns so scripts/synth/ASIC/set_libs.tcl picks the right corner/view
#      file out of each directory (see the comments below).
#
#   4. Run any ASIC workflow as usual, e.g.:
#
#        ./scripts/run_SYNTH_ASIC_LOCAL.sh -module MersenneTwister
#
# Nothing else needs to change: projectStructure.sh sources this file (when present) before
# declaring LIB_SYNTH_ASIC_*, and only falls back to the crheepto_wip reference-PDK default when
# a variable is left unset here.
# ==============================================================================================

# Directory containing your standard-cell timing/power library (.db).
export LIB_SYNTH_ASIC_CELLS="/path/to/your/pdk/stdcells"

# Directory containing your I/O pad library (.db). If your flow has no dedicated pad library,
# point this at an empty directory -- the glob below will then simply match nothing.
export LIB_SYNTH_ASIC_PADS="/path/to/your/pdk/pads"

# Directory containing your memory/macro libraries (.db).
export LIB_SYNTH_ASIC_MEMORIES="/path/to/your/pdk/memories"

# Glob patterns selecting one file per directory above (e.g. the worst-case/slow corner).
# Defaults (used when these are left unset) match this repository's reference PDK's naming:
#   LIB_SYNTH_ASIC_CELLS_GLOB     defaults to "*wc_ccs.db"
#   LIB_SYNTH_ASIC_PADS_GLOB      defaults to "*wcz.db"
#   LIB_SYNTH_ASIC_MEMORIES_GLOB  defaults to "*ss*1p08*125*.db"
# Uncomment and adapt if your library uses different suffixes, e.g. for a generic
# open-source PDK such as Nangate45 or SkyWater sky130:
# export LIB_SYNTH_ASIC_CELLS_GLOB="*.db"
# export LIB_SYNTH_ASIC_PADS_GLOB="*.db"
# export LIB_SYNTH_ASIC_MEMORIES_GLOB="*.db"
