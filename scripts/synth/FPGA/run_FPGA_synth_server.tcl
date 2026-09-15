# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# Retrive the Project Root from the eviromental variable (Set by the Bash script)
set PROJECT_ROOT					$::env(PROJECT_ROOT)
set MODULE_NAME						$::env(MODULE_NAME)
set TOP_SYNTH_FPGA					$::env(TOP_SYNTH_FPGA)
set PRJ_FILE_SYNTH_FPGA				$::env(PRJ_FILE_SYNTH_FPGA)
set FPGA_PART						$::env(FPGA_PART)
set XDC_SYNTH_FPGA_CONSTRAINT		$::env(XDC_SYNTH_FPGA_CONSTRAINT)
set REPORT_SYNTH_FPGA_TIMING		$::env(REPORT_SYNTH_FPGA_TIMING)
set REPORT_SYNTH_FPGA_UTILIZATION	$::env(REPORT_SYNTH_FPGA_UTILIZATION)
set REPORT_SYNTH_FPGA_POWER			$::env(REPORT_SYNTH_FPGA_POWER)
set REPORT_SYNTH_FPGA_SUMMARY		$::env(REPORT_SYNTH_FPGA_SUMMARY)
set NETLIST_SYNTH_FPGA				$::env(NETLIST_SYNTH_FPGA)
set DCP_SYNTH_FPGA					$::env(DCP_SYNTH_FPGA)

if {[info exists ::env(SYNTH_PARAMETER_OVERRIDES)]} {
	set SYNTH_PARAMETER_OVERRIDES [string trim $::env(SYNTH_PARAMETER_OVERRIDES)]
} else {
	set SYNTH_PARAMETER_OVERRIDES ""
}

# Open the "Source File List" file in read mode
set fd_prj [open ${PRJ_FILE_SYNTH_FPGA} r]

# Read lines until I reach the EOF (gets return -1)
while {[gets $fd_prj line] >= 0} {
	# remove trailing and heading spaces and special characters (such as "\n")
	set line [string trim $line]

	# skip empty lines and comments
	if {$line eq ""} { continue }
	if {[string match "#*" $line]} { continue }

	# Compile the SV file at the current line
	read_verilog -sv [file join $PROJECT_ROOT $line]
}

# Close the "Source File List" when all lines are read!
close $fd_prj

# Read the common constraints used for FPGA synthesis
read_xdc ${XDC_SYNTH_FPGA_CONSTRAINT}

if {$SYNTH_PARAMETER_OVERRIDES eq ""} {
	synth_design -top $TOP_SYNTH_FPGA -part $FPGA_PART
} else {
	set SYNTH_PARAMETER_LIST [split $SYNTH_PARAMETER_OVERRIDES " "]
	puts "Applying synthesis parameter overrides: $SYNTH_PARAMETER_LIST"
	synth_design -top $TOP_SYNTH_FPGA -part $FPGA_PART -generic $SYNTH_PARAMETER_LIST
}

# Generate reports about the Synthetized design
report_timing_summary	-file $REPORT_SYNTH_FPGA_TIMING
report_utilization		-file $REPORT_SYNTH_FPGA_UTILIZATION
report_power			-file $REPORT_SYNTH_FPGA_POWER

# Save a compact CSV summary for plotting on the host machine.
proc count_primitive_group {primitive_group} {
	return [llength [get_cells -hier -filter "PRIMITIVE_GROUP == $primitive_group"]]
}

proc count_cells_by_filter {filter_expression} {
	return [llength [get_cells -hier -filter $filter_expression]]
}

set SUMMARY_LUT_LOGIC	[count_primitive_group LUT]
set SUMMARY_LUT_MEMORY	[count_cells_by_filter {REF_NAME =~ RAMD* || REF_NAME =~ RAMS*}]
set SUMMARY_LUT_SHIFT	[count_cells_by_filter {REF_NAME =~ SRL*}]
set SUMMARY_LUT		[expr {$SUMMARY_LUT_LOGIC + $SUMMARY_LUT_MEMORY + $SUMMARY_LUT_SHIFT}]
set SUMMARY_FF		[count_primitive_group FLOP_LATCH]
set SUMMARY_DSP		[count_cells_by_filter {PRIMITIVE_GROUP == DSP || REF_NAME =~ DSP*}]
set SUMMARY_BRAM	[count_cells_by_filter {PRIMITIVE_GROUP == BLOCKRAM || REF_NAME =~ RAMB*}]
set SUMMARY_WNS		""
set SUMMARY_CRITICAL_PATH ""

set timing_paths [get_timing_paths -max_paths 1]
if {[llength $timing_paths] > 0} {
	set worst_path [lindex $timing_paths 0]
	set SUMMARY_WNS [get_property SLACK $worst_path]
	if {[catch {set SUMMARY_CRITICAL_PATH [get_property DATAPATH_DELAY $worst_path]}]} {
		set SUMMARY_CRITICAL_PATH ""
	}
}

set fd_summary [open $REPORT_SYNTH_FPGA_SUMMARY w]
puts $fd_summary "lut,ff,dsp,bram,wns,critical_path,lut_logic,lut_memory,lut_shift"
puts $fd_summary "$SUMMARY_LUT,$SUMMARY_FF,$SUMMARY_DSP,$SUMMARY_BRAM,$SUMMARY_WNS,$SUMMARY_CRITICAL_PATH,$SUMMARY_LUT_LOGIC,$SUMMARY_LUT_MEMORY,$SUMMARY_LUT_SHIFT"
close $fd_summary

# Save the Synthetized design
write_checkpoint -force	$DCP_SYNTH_FPGA
write_verilog -force	$NETLIST_SYNTH_FPGA

quit
