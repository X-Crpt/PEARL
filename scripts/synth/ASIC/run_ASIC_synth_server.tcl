# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# Retrive the Project Root from the eviromental variable (Set by the Bash script) 
set PROJECT_ROOT				$::env(PROJECT_ROOT)
set MODULE_NAME					$::env(MODULE_NAME)
set PRJ_FILE_SYNTH_ASIC			$::env(PRJ_FILE_SYNTH_ASIC)
set REPORT_SYNTH_ASIC_TIMING	$::env(REPORT_SYNTH_ASIC_TIMING)
set REPORT_SYNTH_ASIC_AREA		$::env(REPORT_SYNTH_ASIC_AREA)
set REPORT_SYNTH_ASIC_SUMMARY	$::env(REPORT_SYNTH_ASIC_SUMMARY)
set SDF_SYNTH_ASIC				$::env(SDF_SYNTH_ASIC)
set NETLIST_SYNTH_ASIC			$::env(NETLIST_SYNTH_ASIC)
set SDC_SYNTH_ASIC				$::env(SDC_SYNTH_ASIC)
set TCL_SYNTH_ASIC_SET_LIBS		$::env(TCL_SYNTH_ASIC_SET_LIBS)

if {[info exists ::env(SYNTH_PARAMETER_OVERRIDES)]} {
	set SYNTH_PARAMETER_OVERRIDES [string trim $::env(SYNTH_PARAMETER_OVERRIDES)]
} else {
	set SYNTH_PARAMETER_OVERRIDES ""
}

# Define the Components Library used to perform the Synthesis Process
source ${TCL_SYNTH_ASIC_SET_LIBS}

# Open the "Source File List" file in read mode
set fd_prj [open ${PRJ_FILE_SYNTH_ASIC} r]

# Read lines until I reach the EOF (gets return -1)
while {[gets $fd_prj line] >= 0} {	
	# remove trailing and heading spaces and special characters (such as "\n")
	set line [string trim $line]

	# skip empty lines
	if {$line eq ""} { continue }

	# Compile the SV file at the current line
	analyze -f sverilog -lib WORK [file join $PROJECT_ROOT $line]
}

# Close the "Source File List" when all lines are read!
close $fd_prj	

set power_preserve_rtl_hier_names true

if {$SYNTH_PARAMETER_OVERRIDES eq ""} {
	elaborate $MODULE_NAME -lib WORK
} else {
	set SYNTH_PARAMETER_LIST [split $SYNTH_PARAMETER_OVERRIDES " "]
	set SYNTH_PARAMETER_VALUE_LIST [join $SYNTH_PARAMETER_LIST ","]
	puts "Applying synthesis parameter overrides: $SYNTH_PARAMETER_VALUE_LIST"
	elaborate $MODULE_NAME -lib WORK -parameters $SYNTH_PARAMETER_VALUE_LIST
}
link

# Clock
set CLK_PERIOD 0
create_clock -name MY_CLK -period $CLK_PERIOD [get_ports clk_i]
set_dont_touch_network [get_clocks MY_CLK]
set_clock_uncertainty 0.07 [get_clocks MY_CLK]

set_input_delay 	0.5 -max -clock MY_CLK [remove_from_collection [all_inputs] [get_ports clk_i]]
set_output_delay 	0.5 -max -clock MY_CLK [all_outputs]

# set OUT_LOAD [load_of NangateOpenCellLibrary/BUF_X4/A]
# set_load $OUT_LOAD [all_outputs]

compile_ultra

# Generate reports about the Synthetized design
report_timing 	> $REPORT_SYNTH_ASIC_TIMING
report_area 	> $REPORT_SYNTH_ASIC_AREA

proc read_file_text {file_path} {
	set fd [open $file_path r]
	set file_text [read $fd]
	close $fd
	return $file_text
}

proc get_regex_value {file_path pattern} {
	set file_text [read_file_text $file_path]
	if {[regexp -line $pattern $file_text match value]} {
		return $value
	}
	return ""
}

set SUMMARY_AREA [get_regex_value $REPORT_SYNTH_ASIC_AREA {Total cell area:\s+([0-9.+-]+)}]
set SUMMARY_CRITICAL_PATH [get_regex_value $REPORT_SYNTH_ASIC_TIMING {data arrival time\s+([0-9.+-]+)}]

set fd_summary [open $REPORT_SYNTH_ASIC_SUMMARY w]
puts $fd_summary "area,critical_path"
puts $fd_summary "$SUMMARY_AREA,$SUMMARY_CRITICAL_PATH"
close $fd_summary

# Save the Synthetized design, using a flattened version of it (I don't care anymore about the structure I
# defined in the HDL description)
ungroup -all -flatten
change_names -hierarchy -rules verilog

write_sdf							$SDF_SYNTH_ASIC		; # Timing delay file for gate-level simulation
write -f verilog -hierarchy -output $NETLIST_SYNTH_ASIC	; # Gate level description of the circuit
write_sdc 							$SDC_SYNTH_ASIC		; # Timing constraints file used by synthesis and STA

quit
