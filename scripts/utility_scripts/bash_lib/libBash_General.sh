#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

# Guard Function to prevent multiple sourcing (Current Lib is source for different Files)
if [[ -n "${LIB_GENERAL_LOADED+x}" ]]; then
    return
fi
readonly LIB_GENERAL_LOADED=1

# Recreate a directory safely (delete if exists, then mkdir -p).
# WHY: I need a clean local target before pulling from the server.
# SAFETY: refuse empty paths, '/', and anything outside $PROJECT_ROOT.
general_makeFolder_deletePreviuous() {
	local folderPath=$1

	# ---- sanity checks ---------------------------------------------------------
	# empty arg? bail.
	if [[ -z "${folderPath:-}" ]]; then
		echo "ERR general_makeFolder_deletePreviuous: empty path" >&2
		return 1
	fi

	# resolve to absolute; if it doesn't resolve, bail.
	local abs
	abs="$(readlink -f -- "$folderPath")" || {
		echo "ERR general_makeFolder_deletePreviuous: cannot resolve: $folderPath" >&2
		return 1
	}

	# DO NOT touch root or other obvious traps.
	case "$abs" in
		""|"/"|"/home"|"/root")
		echo "ERR general_makeFolder_deletePreviuous: dangerous path: '$abs'" >&2
		return 1
		;;
	esac

	# confine ops under the project root to avoid fat-finger nukes.
	# REQUIRE: $PROJECT_ROOT is set to the repo root (absolute or resolvable).
	local PROJECT_ROOT_ABS
	PROJECT_ROOT_ABS="$(readlink -f -- "$PROJECT_ROOT")" || {
		echo "ERR: PROJECT_ROOT not set/invalid" >&2
		return 1
	}
	if [[ "$abs" != "$PROJECT_ROOT_ABS"/* ]]; then
		echo "ERR: '$abs' is outside PROJECT_ROOT='$PROJECT_ROOT_ABS'" >&2
		return 1
	fi
	# ---------------------------------------------------------------------------

	# remove existing dir (quiet, robust) and recreate it clean.
	if [[ -d "$abs" ]]; then
		rm -rf -- "$abs"
	fi
	mkdir -p -- "$abs"
}


general_makeFolder_noDeletePreviuous () {
	local folderPath=$1

	if [ ! -d "$folderPath" ]; then
		mkdir -p "$folderPath"  # Generate the folder (and parents if needed)
	fi
}

general_createFile_deletePrevious() {
    local filePath="$1"
    
    # Check if the file already exists
    if [ -e "$filePath" ]; then
        rm "$filePath"  # Delete the previous file
    fi
}


general_findFile () {
	local folderPath="$1"
	local fileName="$2"

	# Check if the folder exists
	if [ ! -d "$folderPath" ]; then
		echo "ERROR: Folder '$folderPath' does not exist." >&2
		return 1
	fi

	# Search for the file in the folder and its subdirectories
	local fullPath
	fullPath=$(find "$folderPath" -type f -name "$fileName" 2>/dev/null)

	# Check if the file was found
	if [ -z "$fullPath" ]; then
		echo "❌ File '$fileName' not found in folder '$folderPath'." >&2
		return 1
	fi

	# Convert to path relative to PROJECT_ROOT
	local relativePath
	relativePath=$(realpath --relative-to="$PROJECT_ROOT" "$fullPath")

	echo "$relativePath"
	return 0
}


###############################################################
# general_concatenateArray
# ─────────────────────────
# Joins all elements of an array using a custom separator.
#
# Usage:
#   result=$(general_concatenateArray ", " "${array[@]}")
###############################################################
general_concatenateArray () {
    local separator="$1"
    shift  # remove the separator from $@
    local arr=("$@")

    local result=""
    local last_index=$((${#arr[@]} - 1))

    for i in "${!arr[@]}"; do
        result+="${arr[i]}"
        if [[ $i -lt $last_index ]]; then
            result+="$separator"
        fi
    done

    echo "$result"
}


###############################################################
# general_stringReplace
# ─────────────────────
# Replaces all occurrences of a substring in a target string.
#
# Usage:
#   result=$(general_stringReplace "target" "old" "new")
#
# Example:
#   general_stringReplace "M=8" "=" "_"   → M_8
#   general_stringReplace "M=8" "=" ""    → M8
###############################################################
general_stringReplace () {
    local target="$1"
    local search="$2"
    local replacement="$3"

    # Escape forward slashes in search/replacement
    local escaped_search=$(printf '%s\n' "$search" | sed 's/[^^]/[&]/g; s/\^/\\^/g')
    local escaped_replacement=$(printf '%s\n' "$replacement" | sed 's/[&/\]/\\&/g')

    echo "${target//$search/$replacement}"
}


# USAGE: length=$(general_printArray my_array)
general_getArrayLength () {
	local -n arr=$1   # -n creates a nameref to the passed array name
  	echo "${#arr[@]}"
}

# USAGE: general_printArray "${myArray_name[@]}"
general_printArray () {
  # Iterate over each element in the array
  for element in "$@"; do
    echo "$element"
  done
}


# USAGE: creation_time=$(general_getTime)
general_getTime () {
	local currentTime

	if ! currentTime=$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null); then
		echo "ERROR: Failed to retrieve current time." >&2
		return 1
	fi

	echo "$currentTime"
}

general_showCtrl () {                # usage: show_ctrl "$var"
    printf '%s' "$1" | cat -vE
}

general_showHex () {                 # usage: show_hex  "$var"
    printf '%s' "$1" | hexdump -C
}

#general_getRelativePath () {
#	local targetDirRel="$1"     # e.g. out/
#	local filePathRel="$2"      # e.g. General_Blocks/REGISTERFILE/register_file.vhd
#
#	# Convert both to absolute using PROJECT_ROOT
#	local targetAbs="$PROJECT_ROOT/$targetDirRel"
#	local fileAbs="$PROJECT_ROOT/$filePathRel"
#
#	# Compute relative path from target to file
#	realpath --relative-to="$targetAbs" "$fileAbs"
#}

# Returns relative path from $1 (targetDirRel) to $2 (filePathRel), both relative to $PROJECT_ROOT
# STDOUT: relative path (on success)
# Exit codes:
#   1 = targetDirRel does not exist / cannot be resolved
#   2 = filePathRel  does not exist / cannot be resolved
#   3 = failed to compute relative path
general_getRelativePath () {
    local targetDirRel="$1"   # e.g., out/
    local filePathRel="$2"    # e.g., General_Blocks/REGISTERFILE/register_file.vhd

    # Build absolute paths from PROJECT_ROOT
    local targetAbs="$PROJECT_ROOT/$targetDirRel"
    local fileAbs="$PROJECT_ROOT/$filePathRel"

    # Resolve to canonical absolute paths (quietly)
    local targetAbsResolved fileAbsResolved rel
    targetAbsResolved=$(realpath "$targetAbs" 2>/dev/null) || return 1
    fileAbsResolved=$(realpath "$fileAbs" 2>/dev/null)     || return 2

    # Compute relative path (quietly)
    rel=$(realpath --relative-to="$targetAbsResolved" "$fileAbsResolved" 2>/dev/null) || return 3
    printf '%s\n' "$rel"
}




# general_getFileNameFromPath <path>
# Returns the base file name WITHOUT extension.
# Works with absolute/relative paths; ignores trailing slashes; handles names without dots.
general_getFileNameFromPath() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  p="${p%/}"                 # drop trailing slash if any
  local base="${p##*/}"      # basename
  base="${base%%.*}"         # strip extension (e.g., .vhd, .v, .txt)
  printf '%s\n' "$base"
}

general_stripProjectRoot () {
	local absolutePath="$1"

	# Ensure PROJECT_ROOT ends with no trailing slash
	local cleanRoot="${PROJECT_ROOT%/}"

	# Strip the root prefix if present
	if [[ "$absolutePath" == "$cleanRoot/"* ]]; then
		echo "${absolutePath#$cleanRoot/}"
	else
		echo "$absolutePath"
	fi
}

general_copyMultipleFiles_PCtoPC () {
	local -n relativePaths=$1      # Array of paths relative to PROJECT_ROOT
	local relativeTarget=$2        # Target folder path (also relative to PROJECT_ROOT)

	local fullTarget="$PROJECT_ROOT/$relativeTarget"

	# Create target folder if needed
	mkdir -p "$fullTarget"

	# Go to project root
	cd "$PROJECT_ROOT" || return 1

	for path in "${relativePaths[@]}"; do
		local filename
		filename=$(basename "$path")
		echo "📄 Copying file: \"$path\" → \"$relativeTarget/$filename\""
		cp "$path" "$fullTarget/$filename"
	done

	echo "✅ File Copy Successful"
}


general_reportFolderCleanup () {
	local relativePath="$1"

	# Sanity checks
	if [[ -z "$relativePath" || "$relativePath" == "/" || "$relativePath" == "." || "$relativePath" == "~" ]]; then
		echo "❌ ERROR: Invalid or dangerous folder path: '$relativePath'" >&2
		return 1
	fi

	local fullPath="$PROJECT_ROOT/$relativePath"

	# Ensure path is under PROJECT_ROOT
	if [[ "$fullPath" != "$PROJECT_ROOT/"* ]]; then
		echo "❌ ERROR: Path '$fullPath' is outside of PROJECT_ROOT" >&2
		return 1
	fi

	# Ensure folder exists
	if [[ ! -d "$fullPath" ]]; then
		echo "❌ ERROR: Folder does not exist: $fullPath" >&2
		return 1
	fi

	echo "🧹 Recursively cleaning unwanted files from: $relativePath"

	# Recursively delete all files not matching these extensions
	find "$fullPath" -type f ! \( \
		-name "*.vhd" -o \
		-name "*.vhdl" -o \
		-name "*.txt" -o \
		-name "*.bash" -o \
		-name "*.tcl" -o \
		-name "*.pdf" \
	\) -exec rm -f {} +

	echo "✅ Folder cleaned (recursive)"
}

#################################################################################################
#	DESCRIPTION:	Inverts the order of elements in a Bash array (modifies in-place)
#	USAGE:			general_invertArrayOrder <arrayName>
#					→ The function takes the name of an array (passed by reference),
#					  and updates its content with reversed order.
#	EXAMPLE:
#					my_array=("a" "b" "c")
#					general_invertArrayOrder my_array
#					echo "${my_array[@]}"  # Output: c b a
#################################################################################################
general_invertArrayOrder () {
	local -n array_ref=$1

	local reversed=()
	for (( idx=${#array_ref[@]}-1 ; idx>=0 ; idx-- )); do
		reversed+=( "${array_ref[$idx]}" )
	done

	# Overwrite original array
	array_ref=("${reversed[@]}")
}


general_arrayContainsExact() {
  local -n arr="$1"		# Array	 
  local needle="$2"		# String to search in the array

  for x in "${arr[@]}"; do [[ "$x" == "$needle" ]] && return 0; done
  return 1
}

# ===========================================================================================
#  find_component_path — Locates a component folder by name inside General_Blocks
# -------------------------------------------------------------------------------------------
#  Usage:
#       find_component_path COMPONENT_NAME PROJECT_ROOT
#       => echoes full path to the component (or returns error)
# ===========================================================================================
general_find_component_path() {
    local component="$1"
    local root="$2"
	
    local match
    match=$(find "$root/General_Blocks" -type f -name "${component}.vhd" -print -quit)

    if [ -z "$match" ]; then
        echo "❌ Error: Component file '${component}.vhd' not found under General_Blocks/" >&2
        return 2
    fi

	# Go two directories up: from file → VHDL → ComponentFolder
    local comp_dir
    comp_dir=$(dirname "$(dirname "$match")")
    echo "$comp_dir"
    return 0
}













#general_find_component_path() {
#    local component="$1"
#    local root="$2"
#
#    if [ ! -d "$root/General_Blocks" ]; then
#        echo "❌ Error: '$root' does not contain General_Blocks/" >&2
#        return 1
#    fi
#
#    local match
#    match=$(find "$root/General_Blocks" -type d -name "$component" -print -quit)
#
#    if [ -z "$match" ]; then
#        echo "❌ Error: Component '$component' not found under General_Blocks/" >&2
#        return 2
#    fi
#
#    echo "$match"
#    return 0
#}