# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

set LIB_SYNTH_ASIC_CELLS 		$::env(LIB_SYNTH_ASIC_CELLS)
set LIB_SYNTH_ASIC_PADS 		$::env(LIB_SYNTH_ASIC_PADS)
set LIB_SYNTH_ASIC_MEMORIES 	$::env(LIB_SYNTH_ASIC_MEMORIES)

# Corner/view selection within each library directory. Defaults (set in
# projectStructure.sh) match this repository's own reference PDK naming
# convention; override LIB_SYNTH_ASIC_*_GLOB in
# scripts/config/asic_lib.local.sh if your own library names its .db files
# differently.
set DB_STDCELLS [glob -nocomplain -directory $LIB_SYNTH_ASIC_CELLS	 	-- $::env(LIB_SYNTH_ASIC_CELLS_GLOB)]
set DB_PADS 	[glob -nocomplain -directory $LIB_SYNTH_ASIC_PADS	 	-- $::env(LIB_SYNTH_ASIC_PADS_GLOB)]
set DB_MEMORIES [glob -nocomplain -directory $LIB_SYNTH_ASIC_MEMORIES	-- $::env(LIB_SYNTH_ASIC_MEMORIES_GLOB)]

# target library
set target_library      {}
set target_library  "$DB_STDCELLS $DB_PADS $DB_MEMORIES"

# link library
set link_library "* $target_library"

#debug output info
puts "------------------------------------------------------------------"
puts "USED LIBRARIES"
puts $link_library
puts "------------------------------------------------------------------"

set link_library " * $link_library"
