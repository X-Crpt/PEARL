#pragma once

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// AES-128 adapter for the common BlockFunction interface.
//
// The class hides the CryptoPP calls behind the same generate_block method used by the other block
// functions. This makes it easier to swap AES with another block function inside higher level
// golden models.
// ==============================================================================================

#include "../Common/BlockFunction.hpp"
#include "../Common/bytesNumber.hpp"

class AESBlockFunction : public BlockFunction {
	public:
		AESBlockFunction(size_t output_bytes_in);

		bytesNumber generate_block(
			const bytesNumber& key,
			const bytesNumber& input
		) override;

	private:
		size_t output_bytes;
};
