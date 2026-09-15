#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# Common terminal formatting used by the project scripts.

: "${BASH_PRINT_WIDTH:=92}"

print_line() {
	local char="$1"

	printf '%*s\n' "$BASH_PRINT_WIDTH" '' | tr ' ' "$char"
}

print_center_line() {
	local text="$1"
	local char="$2"
	local text_width=${#text}
	local side_width=$(( (BASH_PRINT_WIDTH - text_width - 2) / 2 ))
	local extra_width=$(( (BASH_PRINT_WIDTH - text_width - 2) % 2 ))
	local left=""
	local right=""

	printf -v left "%*s" "$side_width" ""
	left=${left// /$char}
	printf -v right "%*s" "$((side_width + extra_width))" ""
	right=${right// /$char}

	echo "${left} ${text} ${right}"
}

print_module_header() {
	local module_name="$1"
	local variant_name="$2"
	local params="$3"
	local flows="$4"

	print_line "#"
	print_center_line "MODULE / VARIANT" "#"
	echo "Module:  $module_name"
	echo "Variant: $variant_name"
	echo "Params:  $params"
	echo "Flows:   $flows"
	print_line "#"
	echo
}

print_flow_title() {
	local flow="$1"

	print_line "="
	print_center_line "$flow" "="
}

print_flow_footer() {
	local message="$1"

	print_center_line "$message" "="
	print_line "="
	echo
}

print_phase() {
	local phase_name="$1"

	print_center_line "$phase_name" "-"
}

print_project_log_path() {
	local log_path="$1"

	if [[ -n "${PROJECT_ROOT:-}" ]]; then
		echo "Log: ${log_path#$PROJECT_ROOT/}"
	else
		echo "Log: $log_path"
	fi
}
