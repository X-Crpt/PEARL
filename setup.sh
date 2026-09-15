#!/usr/bin/env bash

# ==============================================================================================
# Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
# Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
#          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
# ----------------------------------------------------------------------------------------------

set -e
set -u
set -o pipefail

PROJECT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
cd "$PROJECT_ROOT"

APT_UPDATED=0

# Detect a usable system package manager, if any. Absence of one (or of sudo)
# is not fatal: install_package() falls back to printing manual instructions,
# including a conda-based option that needs neither.
PKG_MANAGER=""
if command -v apt-get >/dev/null 2>&1; then
	PKG_MANAGER="apt"
elif command -v dnf >/dev/null 2>&1; then
	PKG_MANAGER="dnf"
elif command -v yum >/dev/null 2>&1; then
	PKG_MANAGER="yum"
fi

HAVE_SUDO=0
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
	HAVE_SUDO=1
fi

# install_package <human_name> <conda_package> <apt_package> <dnf/yum_package>
# Tries the detected system package manager first (if sudo works non-interactively),
# and otherwise prints manual options (including a conda one) instead of failing outright.
install_package() {
	local human_name="$1" conda_pkg="$2" apt_pkg="$3" dnf_pkg="$4"

	if [[ "$PKG_MANAGER" == "apt" && "$HAVE_SUDO" -eq 1 ]]; then
		if [[ "$APT_UPDATED" -eq 0 ]]; then
			sudo apt-get update
			APT_UPDATED=1
		fi
		sudo apt-get install -y "$apt_pkg"
		return 0
	fi

	if [[ ( "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ) && "$HAVE_SUDO" -eq 1 ]]; then
		sudo "$PKG_MANAGER" install -y "$dnf_pkg"
		return 0
	fi

	cat >&2 <<EOF
WARNING: could not install $human_name automatically
  (package manager: ${PKG_MANAGER:-none found}, passwordless sudo: $([[ $HAVE_SUDO -eq 1 ]] && echo yes || echo no)).

Install it manually with one of:
  - apt (Debian/Ubuntu, needs sudo):   sudo apt-get install -y $apt_pkg
  - dnf/yum (RHEL/Fedora, needs sudo): sudo dnf install -y $dnf_pkg   # or: sudo yum install -y $dnf_pkg
  - conda (no sudo needed):            conda create -n prng-$conda_pkg -c conda-forge $conda_pkg
                                        then export CPATH/LIBRARY_PATH/LD_LIBRARY_PATH to point
                                        at that environment's include/lib before building.
                                        Note: a conda-forge C/C++ package may need a newer
                                        compiler than an old system GCC to link against (a
                                        libstdc++ ABI mismatch shows up as "undefined reference
                                        to std::__throw_bad_array_new_length()"); see readme.md's
                                        "Troubleshooting Setup on Shared/HPC Machines".
EOF
	return 1
}

echo "Initializing git submodules..."
if ! git submodule update --init --recursive 2>/tmp/prng_submodule_err.$$; then
	cat /tmp/prng_submodule_err.$$ >&2
	echo "Some submodules failed to initialize together; retrying individually" >&2
	echo "(a submodule failing here, e.g. a private one you lack access to, is not fatal" >&2
	echo " unless the workflow you want to run actually needs it)." >&2
	git config --file .gitmodules --get-regexp path | while read -r _ path; do
		if ! git submodule update --init "$path"; then
			echo "  -> could not initialize submodule: $path (continuing)" >&2
		fi
	done
fi
rm -f /tmp/prng_submodule_err.$$

echo "Checking Crypto++..."
if printf '#include <cryptopp/secblock.h>\nint main(){return 0;}\n' \
	| g++ -x c++ - -lcryptopp -o /tmp/prng_cryptopp_check.$$ >/dev/null 2>&1; then
	rm -f /tmp/prng_cryptopp_check.$$
	echo "Crypto++ already installed."
else
	rm -f /tmp/prng_cryptopp_check.$$
	echo "Installing Crypto++..."
	install_package "Crypto++" "cryptopp" "libcrypto++-dev" "cryptopp-devel" || true
fi

echo "Checking Python plotting libraries..."
if python3 - <<'PY' >/dev/null 2>&1
import matplotlib
import numpy
PY
then
	echo "Python plotting libraries already installed."
else
	echo "Installing Python plotting libraries..."
	install_package "matplotlib" "matplotlib" "python3-matplotlib" "python3-matplotlib" || true
	install_package "numpy" "numpy" "python3-numpy" "python3-numpy" || true
fi

echo "Setup completed."
