// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "DP.hpp"
#include "../AES_128/AESBlockFunction.hpp"
#include "../Keccak/Keccak.hpp"
#include <memory>
#include <stdexcept>

DP::DP(
	const bytesNumber& A_in,
	const bytesNumber& B_in,
	size_t seed_bytes_in,
	primitive_core_e prg_type_in,
	primitive_core_e extractor_type_in
)
	: A					(A_in),
	  B					(B_in),
	  seed				(seed_bytes_in),
	  prg_type			(prg_type_in),
	  extractor_type	(extractor_type_in) {
	if (A_in.size() == 0) {
		throw invalid_argument("ERROR: A or B size cannot be a 0 bytes number");
	}
	if (A_in.size() != B_in.size()) {
		throw invalid_argument("ERROR: A and B must have the same size");
	}
	if (seed_bytes_in == 0) {
		throw invalid_argument("ERROR: seed size cannot be 0");
	}
	if ((A.size() + seed.size()) > Keccak::get_state_bytes()) {
		throw invalid_argument("ERROR: DP extractor input does not fit in the Keccak-f[1600] state");
	}
	if ((extractor_type == PRIMITIVE_CORE_AES) && ((A.size() + seed.size()) > 16)) {
		throw invalid_argument("ERROR: AES extractor can generate at most 128 bits");
	}
	if ((prg_type == PRIMITIVE_CORE_AES) && (A.size() > 16)) {
		throw invalid_argument("ERROR: AES PRG can generate at most 128 bits");
	}

	switch (prg_type) {
		case PRIMITIVE_CORE_KECCAK:
			prg_block = make_unique<Keccak>(A.size());
			break;

		case PRIMITIVE_CORE_AES:
			prg_block = make_unique<AESBlockFunction>(A.size());
			break;

		default:
			throw invalid_argument("ERROR: Unsupported DP PRG type");
	}

	switch (extractor_type) {
		case PRIMITIVE_CORE_KECCAK:
			extractor_block = make_unique<Keccak>(A.size() + seed.size());
			break;

		case PRIMITIVE_CORE_AES:
			extractor_block = make_unique<AESBlockFunction>(A.size() + seed.size());
			break;

		default:
			throw invalid_argument("ERROR: Unsupported DP extractor type");
	}

	// Initialize the internal states of the DP Golden Model
	seed.resetValue();
	isSeeded = 0;		// The object is still not seeded

	// Start the DP operations from the "Even" operation path
	isExtractionEven = 1;
}

bytesNumber DP::generate_random_number(void) {
	if (!isSeeded) {
		throw runtime_error("ERROR: DP must be reseeded before generating random numbers");
	}

	bytesNumber X_out(A.size());

	if (isExtractionEven) {
		bytesNumber extraction_out = extract(A);
		
		// From the output of the extractor, extract the new seed and the vector to feed the prng to generate the 
		// new state A
		X_out = extraction_out.getSlice(A.size() - 1, 0);
		seed = extraction_out.getSlice(A.size() + seed.size() - 1, A.size());

		// Generate teh new state A
		A = prg(X_out);
	} else {
		bytesNumber extraction_out = extract(B);

		// From the output of the extractor, extract the new seed and the vector to feed the prng to generate the 
		// new state B
		X_out = extraction_out.getSlice(A.size() - 1, 0);
		seed = extraction_out.getSlice(A.size() + seed.size() - 1, A.size());

		// Generate teh new state B
		B = prg(X_out);
	}

	isExtractionEven = !isExtractionEven;
	return seed;
}

void DP::reseed(const bytesNumber& entropy_input) {
	if (entropy_input.size() != seed.size()) {
		throw invalid_argument("ERROR: entropy input size does not match the configured DP seed size");
	}

	seed = entropy_input;
	isSeeded = 1;

	// Start again from the A-side extraction after each reseed
	isExtractionEven = 1;
}

void DP::reset() {
	// Reset the internal states of the DP Golden Model to their initial values
	seed.resetValue();
	isSeeded = 0;
	isExtractionEven = 1;
}

bytesNumber DP::extract(const bytesNumber& memory_in) const {
	switch (extractor_type) {
		case PRIMITIVE_CORE_KECCAK: {
			if (memory_in.size() != A.size()) {
				throw invalid_argument("ERROR: DP extractor memory size does not match the configured memory size");
			}
			
			// generate the input vector to feed as Keccak input as:
			// {ZERO_PAD, seed, memorty_in}
			// The Zero Pad is used to guarantee the input vecor has the exact number of bits that Keccak requires
			bytesNumber keccak_input = memory_in;
			keccak_input.appendHighSide(seed);
			keccak_input.zeroPad(Keccak::get_state_bytes());
			
			return extractor_block->generate_block(keccak_input);
		}
		case PRIMITIVE_CORE_AES: {
			if (memory_in.size() != A.size()) {
				throw invalid_argument("ERROR: DP extractor memory size does not match the configured memory size");
			}

			bytesNumber aes_key = seed;
			aes_key.setSize(16);
			return extractor_block->generate_block(aes_key, memory_in);
		}

		default:
			throw invalid_argument("ERROR: Unsupported DP extractor type");
	}
}

bytesNumber DP::prg(const bytesNumber& seed_in) const {
	switch (prg_type) {
		case PRIMITIVE_CORE_KECCAK: {
			bytesNumber prg_input = seed_in;
			prg_input.appendHighSide(seed);
			return prg_block->generate_block(prg_input);
		}
		case PRIMITIVE_CORE_AES: {
			bytesNumber aes_key = seed;
			aes_key.setSize(16);
			return prg_block->generate_block(aes_key, seed_in);
		}
		default:
			throw invalid_argument("ERROR: Unsupported DP PRG type");
	}
}
