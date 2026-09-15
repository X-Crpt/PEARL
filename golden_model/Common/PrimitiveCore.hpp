#pragma once

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include <cstdint>

// Same values used in rtl/PRNG_common/primitive_pkg.sv.
// A primitive core is a stateless n-bit -> n-bit transform used as a building
// block inside a higher-level PRNG architecture.
enum primitive_core_e : int32_t {
	PRIMITIVE_CORE_KECCAK	= 0,
	PRIMITIVE_CORE_AES		= 1
};
