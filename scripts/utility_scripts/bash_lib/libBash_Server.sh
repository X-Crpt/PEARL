#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

set -e				# Fail if any command exits with an error
set -u				# Fail if an undefined variable is used
set -o pipefail		# Fail a pipeline if any command inside it fails

# Guard Function to prevent multiple sourcing (Current Lib is source for different Files)
if [[ -v LIB_SERVER_LOADED ]]; then
    return
fi
readonly LIB_SERVER_LOADED=1

# Retrive constants about the paths of folders/files/scripts in the project
source "${PROJECT_ROOT}/scripts/utility_scripts/projectStructure.sh"

# Check if there is a Server Configuration file, and if not just run again the Setup Script 
if [[ ! -f "$SERVER_CONFIG_FILE" ]]; then
	echo "Server config not found at: $SERVER_CONFIG_FILE" >&2
	echo "Running: $SCRIPT_SERVER_CONFIG" >&2
	$SCRIPT_SERVER_CONFIG
fi

if [[ -z "${SERVER_USER:-}" || -z "${SERVER_HOST:-}" || -z "${SERVER_PORT:-}" || -z "${SERVER_SSH_KEY:-}" ]]; then
	source "$SERVER_CONFIG_FILE"
fi
projectStructure_defineServerPaths

# Define the Server Login
readonly server_Login="$SERVER_USER@$SERVER_HOST"

#############################################################################
#						# Function Definition #								#
#############################################################################

server_executeScript () {
	local server_scriptPath_rel
	server_scriptPath_rel="$(server_hostPathToProjectRelative "$1")" || return 1
	shift

	local server_scriptPath="$SERVER_BASE_FOLDER/$server_scriptPath_rel"

	local quoted_args=""
	local arg
	for arg in "$@"; do
		quoted_args+=" $(printf '%q' "$arg")"
	done

	if ssh -i "$SERVER_SSH_KEY" -t -p "$SERVER_PORT" "$server_Login" "bash \"$server_scriptPath\"$quoted_args"; then
		return 0
	else
		local ssh_status=$?
		echo "ERROR: Connection to server failed or script exited with code $ssh_status" >&2
		return 1
	fi
}


server_endSession () {
	exit 
}

server_hostPathToProjectRelative () {
	if [[ $# -lt 1 ]]; then
		echo "ERROR: missing host path" >&2
		return 1
	fi

	local hostPath="$1"

	if [[ -z "$hostPath" ]]; then
		echo "ERROR: empty host path" >&2
		return 1
	fi

	local projectRootAbs
	projectRootAbs="$(readlink -f -- "$PROJECT_ROOT")" || {
		echo "ERROR: PROJECT_ROOT is not valid: $PROJECT_ROOT" >&2
		return 1
	}

	local hostPathAbs
	if [[ "$hostPath" = /* ]]; then
		hostPathAbs="$(readlink -m -- "$hostPath")"
	else
		hostPathAbs="$(readlink -m -- "$PROJECT_ROOT/$hostPath")"
	fi

	case "$hostPathAbs" in
		"$projectRootAbs")
			printf '.\n'
			;;
		"$projectRootAbs"/*)
			printf '%s\n' "${hostPathAbs#$projectRootAbs/}"
			;;
		*)
			echo "ERROR: '$hostPathAbs' is outside PROJECT_ROOT='$projectRootAbs'" >&2
			return 1
			;;
	esac
}

server_hostPathToServerPath () {
	local relativePath
	relativePath="$(server_hostPathToProjectRelative "$1")" || return 1

	if [[ "$relativePath" == "." ]]; then
		printf '%s\n' "$SERVER_BASE_FOLDER"
	else
		printf '%s/%s\n' "${SERVER_BASE_FOLDER%/}" "$relativePath"
	fi
}

server_shareFolder_PCtoServer () {
  local pcFolderPath="$1"   # absolute path or path relative to PROJECT_ROOT
  local serverTargetPath_relative=""
  local relativeFolderPath

  if [[ $# -ge 2 ]]; then
    serverTargetPath_relative="$2"
  fi

  relativeFolderPath="$(server_hostPathToProjectRelative "$pcFolderPath")" || return 1
  if [[ -z "$serverTargetPath_relative" ]]; then
    serverTargetPath_relative="$relativeFolderPath"
  fi

  local serverTargetPath="$SERVER_BASE_FOLDER/$serverTargetPath_relative"

  local absoluteFolder="$PROJECT_ROOT/$relativeFolderPath"
  [[ -d "$absoluteFolder" ]] || { echo "ERROR: Source folder does not exist: $absoluteFolder" >&2; return 1; }

  # echo "📁 Sending folder to Server: \"$relativeFolderPath\" → \"$serverTargetPath\""

  ssh -i "$SERVER_SSH_KEY" -p "$SERVER_PORT" "$server_Login" "mkdir -p \"$serverTargetPath\"" || return 1
  cd "$PROJECT_ROOT" || return 1

  # CONTENTS of source → target
  if rsync -az --quiet -e "ssh -i $SERVER_SSH_KEY -p $SERVER_PORT" \
    "$relativeFolderPath/" "$server_Login:${serverTargetPath%/}/"; then
	# echo "✅ Folder Sharing Successful"; 
	return;
  else 
	local rc=$?
	echo "❌ rsync failed ($rc)" >&2; 
	return $rc; 
  fi
}

server_shareFolder_ServerToPC () {
	local pcFolderPath="$1"   # absolute path or path relative to PROJECT_ROOT
	local serverSourcePath_relative=""
	local relativeFolderPath

	if [[ $# -ge 2 ]]; then
		serverSourcePath_relative="$2"
	fi

	relativeFolderPath="$(server_hostPathToProjectRelative "$pcFolderPath")" || return 1
	if [[ -z "$serverSourcePath_relative" ]]; then
		serverSourcePath_relative="$relativeFolderPath"
	fi

	local pcTargetPath="$PROJECT_ROOT/$relativeFolderPath"

	# echo "📂 Receiving folder from Server: \"$serverSourcePath_relative\" → \"$relativeFolderPath\""

	cd "$PROJECT_ROOT" || { echo "❌ Cannot cd to PROJECT_ROOT: $PROJECT_ROOT" >&2; return 1; }
	mkdir -p "$pcTargetPath" || { echo "❌ Cannot create $pcTargetPath" >&2; return 1; }

	if rsync -az --quiet -e "ssh -i $SERVER_SSH_KEY -p $SERVER_PORT" \
		--rsync-path="cd \"$SERVER_BASE_FOLDER\" && rsync" \
		"$server_Login:$serverSourcePath_relative/" "$pcTargetPath/"; then
		# echo "✅ Retrieved into: $relativeFolderPath/"
		return;
	else
		local rc=$?
		echo "❌ rsync failed (code $rc)" >&2
		return $rc
	fi
}


server_shareMultipleFiles_PCtoServer () {
	local -n relativePaths=$1     # Array of paths relative to PROJECT_ROOT
	local server_basePath="$2"    # Target folder on server

	# Go to root of project to make rsync --relative work correctly
	cd "$PROJECT_ROOT" || exit 1

	# Print each file being shared
	# for relPath in "${relativePaths[@]}"; do
	# 	echo "📤 Sending file to Server: \"$relPath\""
	# done

	# Create remote base folder if needed
	ssh -i "$SERVER_SSH_KEY" -p "$SERVER_PORT" "$server_Login" "mkdir -p \"$server_basePath\""

	# Perform transfer with path structure preserved
	rsync -azR --quiet -e "ssh -i $SERVER_SSH_KEY -p $SERVER_PORT" "${relativePaths[@]}" "$server_Login:$server_basePath/"

	# echo "✅ File Sharing Successful"
}

server_shareMultipleFiles_ServerToPC () {
	local -n relativePaths=$1      # Array of relative paths inside server_basePath
	local server_basePath="$2"     # Base directory on the server

	# Go to the project root on the PC
	cd "$PROJECT_ROOT" || exit 1

	# Print each file being retrieved
	for relPath in "${relativePaths[@]}"; do
		echo "📥 Receiving file from Server: \"$relPath\""
	done

	# Run rsync with --relative to preserve directory structure
	if rsync -azR --quiet -e "ssh -i $SERVER_SSH_KEY -p $SERVER_PORT" \
		"$server_Login:$server_basePath/${relativePaths[@]}" .; then
		# echo "✅ File Retrieval Successful"
		return;
	else
		echo "❌ ERROR: File Retrieval Failed" >&2
		return 1
	fi
}
