#pragma once

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "../Common/PRNG.hpp"
#include "../Common/bytesNumber.hpp"
#include <cstddef>
#include <cstdint>
#include <random>

using namespace std;

// Return codes for MersenneTwister Golden Model operations
static constexpr int MersenneTwister_USAGE_FAILURE	= 2;
static constexpr int MersenneTwister_FAILURE		= 1;
static constexpr int MersenneTwister_SUCCESS		= 0;

class MersenneTwister : public PRNG {
	public:
		MersenneTwister						(size_t output_bits_in);

		bytesNumber	generate_random_number	() override;
		void 		reseed					(const bytesNumber& seed_in) override;
		void 		reset					() override;

		size_t get_output_bits	() const;
		size_t get_output_bytes	() const;

	private:
		static constexpr size_t CORE_WORD_BITS = 32;

		size_t	output_bits;
		size_t	output_bytes;
		mt19937	mt_core;

		uint32_t	seed_to_core_word		(const bytesNumber& seed_in) const;
		void 		mask_unused_output_bits	(bytesNumber& output) const;
};
