#pragma once

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Common interface for golden models that behave like complete pseudo-random generators.
//
// A PRNG object owns some internal state, can be reseeded, and can generate one configured output
// word. The output size is fixed when the object is created, like the related RTL parameter.
// ==============================================================================================

#include "bytesNumber.hpp"

class PRNG {
	public:
		virtual ~PRNG() = default;

		virtual void reseed(const bytesNumber& seed_in) = 0;
		virtual bytesNumber generate_random_number() = 0;
		virtual void reset() = 0;
};
