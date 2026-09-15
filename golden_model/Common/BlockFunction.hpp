#pragma once

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Common interface for golden models used as block transformations.
//
// Some blocks use only one input, like a fixed Keccak permutation. Other blocks also need a key,
// like AES. For this reason the interface exposes both versions. A derived class can override only
// the one it really supports.
// ==============================================================================================

#include "bytesNumber.hpp"
#include <cstddef>

class BlockFunction {
	public:
		virtual ~BlockFunction() = default;

		virtual bytesNumber generate_block(const bytesNumber& input);
		virtual bytesNumber generate_block(const bytesNumber& key, const bytesNumber& input);
};
