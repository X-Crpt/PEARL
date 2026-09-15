// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "MersenneTwister.hpp"
#include <stdexcept>

// Create a MersenneTwister golden model with a programmable output size.
// The output size is expressed in bits because the RTL parameter L is also in bits.
MersenneTwister::MersenneTwister(size_t output_bits_in)
	: output_bits(output_bits_in),
	  output_bytes((output_bits_in + 7) / 8),
	  mt_core(0) {
	if (output_bits == 0) {
		throw invalid_argument("ERROR: MersenneTwister output size cannot be 0 bits");
	}
}

bytesNumber MersenneTwister::generate_random_number() {
	bytesNumber output(output_bytes);
	size_t bits_written = 0;

	// Fill the output starting from the LSB side, exactly like the SV wrapper:
	// first MT19937 word goes in the low 32 bits, second word above it, and so on.
	while (bits_written < output_bits) {
		uint32_t word = mt_core();

		for (size_t bit_idx = 0; (bit_idx < CORE_WORD_BITS) && (bits_written < output_bits); bit_idx++) {
			size_t output_byte_idx = bits_written / 8;
			size_t output_bit_idx = bits_written % 8;

			output[output_byte_idx] |= static_cast<uint8_t>(((word >> bit_idx) & 1U) << output_bit_idx);
			bits_written++;
		}
	}

	mask_unused_output_bits(output);
	return output;
}

void MersenneTwister::reseed(const bytesNumber& seed_in) {
	mt_core.seed(seed_to_core_word(seed_in));
}

void MersenneTwister::reset() {
	mt_core.seed(0);
}

size_t MersenneTwister::get_output_bits() const {
	return output_bits;
}

size_t MersenneTwister::get_output_bytes() const {
	return output_bytes;
}

uint32_t MersenneTwister::seed_to_core_word(const bytesNumber& seed_in) const {
	uint32_t core_seed = 0;
	size_t bytes_to_read = (seed_in.size() < 4) ? seed_in.size() : 4;

	for (size_t byte_idx = 0; byte_idx < bytes_to_read; byte_idx++) {
		core_seed |= static_cast<uint32_t>(seed_in[byte_idx]) << (8 * byte_idx);
	}

	if (output_bits < CORE_WORD_BITS) {
		core_seed &= (1U << output_bits) - 1U;
	}

	return core_seed;
}

void MersenneTwister::mask_unused_output_bits(bytesNumber& output) const {
	size_t used_bits_in_msb_byte = output_bits % 8;

	if (used_bits_in_msb_byte == 0) {
		return;
	}

	uint8_t mask = static_cast<uint8_t>((1U << used_bits_in_msb_byte) - 1U);
	output[output.size() - 1] &= mask;
}
