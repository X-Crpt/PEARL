#pragma once

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "../Common/BlockFunction.hpp"
#include "../Common/bytesNumber.hpp"
#include <array>
#include <cstdint>

using namespace std;

// Return codes for Keccak Golden Model operations
static constexpr int KECCAK_USAGE_FAILURE	= 2;
static constexpr int KECCAK_FAILURE			= 1;
static constexpr int KECCAK_SUCCESS			= 0;

class Keccak : public BlockFunction {
	public:
		Keccak(size_t output_bytes_in);

		bytesNumber generate_block(const bytesNumber& input) override;

		static bytesNumber keccak_f1600(const bytesNumber& input_state);
		static constexpr size_t get_state_bytes(void) { return STATE_BYTES; }

	private:
		static constexpr size_t STATE_LANES	= 25;
		static constexpr size_t STATE_WORDS	= 50;
		static constexpr size_t STATE_BYTES	= 200;
		static constexpr size_t NROUNDS		= 24;

		size_t output_bytes;

		static const array<uint64_t, NROUNDS> ROUND_CONSTANTS;
		static const unsigned int ROTATION_CONSTANTS[5][5];

		static uint64_t rol(uint64_t value, unsigned int offset);
		static void keccak_f1600_state_permute(array<uint64_t, STATE_LANES>& state);
		static array<uint64_t, STATE_LANES> words_to_lanes(const array<uint32_t, STATE_WORDS>& state_words);
		static array<uint32_t, STATE_WORDS> lanes_to_words(const array<uint64_t, STATE_LANES>& state_lanes);
};
