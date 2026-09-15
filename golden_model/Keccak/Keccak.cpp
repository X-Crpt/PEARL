// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "Keccak.hpp"
#include <stdexcept>

using namespace std;

const array<uint64_t, Keccak::NROUNDS> Keccak::ROUND_CONSTANTS = {
	0x0000000000000001ULL, 0x0000000000008082ULL,
	0x800000000000808aULL, 0x8000000080008000ULL,
	0x000000000000808bULL, 0x0000000080000001ULL,
	0x8000000080008081ULL, 0x8000000000008009ULL,
	0x000000000000008aULL, 0x0000000000000088ULL,
	0x0000000080008009ULL, 0x000000008000000aULL,
	0x000000008000808bULL, 0x800000000000008bULL,
	0x8000000000008089ULL, 0x8000000000008003ULL,
	0x8000000000008002ULL, 0x8000000000000080ULL,
	0x000000000000800aULL, 0x800000008000000aULL,
	0x8000000080008081ULL, 0x8000000000008080ULL,
	0x0000000080000001ULL, 0x8000000080008008ULL
};

const unsigned int Keccak::ROTATION_CONSTANTS[5][5] = {
	{0,		36,	3,	41,	18	},
	{1,		44,	10,	45,	2	},
	{62,	6,	43,	15,	61	},
	{28,	55,	25,	21,	56	},
	{27,	20,	39,	8,	14	}
};

Keccak::Keccak(size_t output_bytes_in)
	: output_bytes(output_bytes_in) {
	if (output_bytes == 0) {
		throw invalid_argument("ERROR: Keccak output size cannot be 0 bytes");
	}
	if (output_bytes > STATE_BYTES) {
		throw invalid_argument("ERROR: Keccak output size cannot be larger than 200 bytes");
	}
}

bytesNumber Keccak::generate_block(const bytesNumber& input) {
	bytesNumber keccak_input = input;

	keccak_input.zeroPad(STATE_BYTES);

	bytesNumber keccak_output = keccak_f1600(keccak_input);
	return keccak_output.getSlice(output_bytes - 1, 0);
}

uint64_t Keccak::rol(uint64_t value, unsigned int offset) {
	if (offset == 0) {
		return value;
	}

	return (value << offset) | (value >> (64 - offset));
}

void Keccak::keccak_f1600_state_permute(array<uint64_t, STATE_LANES>& state) {
	array<uint64_t, 5> column_parity;
	array<uint64_t, 5> theta_correction;
	array<uint64_t, STATE_LANES> rotated_state;

	for (size_t round = 0; round < NROUNDS; round++) {
		// Theta
		for (size_t x = 0; x < 5; x++) {
			column_parity[x] = state[(5 * 0) + x] ^
							   state[(5 * 1) + x] ^
							   state[(5 * 2) + x] ^
							   state[(5 * 3) + x] ^
							   state[(5 * 4) + x];
		}

		for (size_t x = 0; x < 5; x++) {
			theta_correction[x] = column_parity[(x + 4) % 5] ^ rol(column_parity[(x + 1) % 5], 1);
		}

		for (size_t x = 0; x < 5; x++) {
			for (size_t y = 0; y < 5; y++) {
				state[(5 * y) + x] ^= theta_correction[x];
			}
		}

		// Rho and Pi
		rotated_state.fill(0);
		for (size_t x = 0; x < 5; x++) {
			for (size_t y = 0; y < 5; y++) {
				size_t out_x = y;
				size_t out_y = (2 * x + 3 * y) % 5;
				rotated_state[(5 * out_y) + out_x] = rol(state[(5 * y) + x], ROTATION_CONSTANTS[x][y]);
			}
		}

		// Chi
		for (size_t x = 0; x < 5; x++) {
			for (size_t y = 0; y < 5; y++) {
				state[(5 * y) + x] = rotated_state[(5 * y) + x] ^
					((~rotated_state[(5 * y) + ((x + 1) % 5)]) & rotated_state[(5 * y) + ((x + 2) % 5)]);
			}
		}

		// Iota
		state[0] ^= ROUND_CONSTANTS[round];
	}
}

bytesNumber Keccak::keccak_f1600(const bytesNumber& input_state) {
	if (input_state.size() > STATE_BYTES) {
		throw invalid_argument("ERROR: Keccak-f[1600] input state cannot be larger than 200 bytes");
	}

	bytesNumber padded_input = input_state;
	padded_input.zeroPad(STATE_BYTES);

	array<uint32_t, STATE_WORDS> state_words = {};
	for (size_t word_idx = 0; word_idx < STATE_WORDS; word_idx++) {
		uint32_t current_word = 0;
		for (size_t byte_idx = 0; byte_idx < 4; byte_idx++) {
			current_word |= static_cast<uint32_t>(padded_input[(4 * word_idx) + byte_idx]) << (8 * byte_idx);
		}
		state_words[word_idx] = current_word;
	}

	array<uint64_t, STATE_LANES> state_lanes = words_to_lanes(state_words);
	keccak_f1600_state_permute(state_lanes);
	state_words = lanes_to_words(state_lanes);

	bytesNumber output_state(STATE_BYTES);
	for (size_t word_idx = 0; word_idx < STATE_WORDS; word_idx++) {
		for (size_t byte_idx = 0; byte_idx < 4; byte_idx++) {
			output_state[(4 * word_idx) + byte_idx] = static_cast<uint8_t>((state_words[word_idx] >> (8 * byte_idx)) & 0xFF);
		}
	}

	return output_state;
}

array<uint64_t, Keccak::STATE_LANES> Keccak::words_to_lanes(const array<uint32_t, STATE_WORDS>& state_words) {
	array<uint64_t, STATE_LANES> state_lanes = {};

	for (size_t lane_idx = 0; lane_idx < STATE_LANES; lane_idx++) {
		uint64_t low_word = static_cast<uint64_t>(state_words[2 * lane_idx]);
		uint64_t high_word = static_cast<uint64_t>(state_words[(2 * lane_idx) + 1]);
		state_lanes[lane_idx] = low_word | (high_word << 32);
	}

	return state_lanes;
}

array<uint32_t, Keccak::STATE_WORDS> Keccak::lanes_to_words(const array<uint64_t, STATE_LANES>& state_lanes) {
	array<uint32_t, STATE_WORDS> state_words = {};

	for (size_t lane_idx = 0; lane_idx < STATE_LANES; lane_idx++) {
		state_words[2 * lane_idx] = static_cast<uint32_t>(state_lanes[lane_idx] & 0xFFFFFFFFULL);
		state_words[(2 * lane_idx) + 1] = static_cast<uint32_t>((state_lanes[lane_idx] >> 32) & 0xFFFFFFFFULL);
	}

	return state_words;
}
