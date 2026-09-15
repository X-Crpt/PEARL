#pragma once

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "../Common/BlockFunction.hpp"
#include "../Common/PrimitiveCore.hpp"
#include "../Common/bytesNumber.hpp"
#include <memory>

using namespace std;

// Return codes for ctr_drbg Golden Model operations
static constexpr int ctr_drbg_USAGE_FAILURE	= 2;
static constexpr int ctr_drbg_FAILURE		= 1;
static constexpr int ctr_drbg_SUCCESS		= 0;

class ctr_drbg {
	public:
		ctr_drbg(
			size_t outlen_bytes,
			size_t keylen_bytes,
			int32_t reseed_counter_max_in,
			primitive_core_e block_function_type = PRIMITIVE_CORE_AES
		);
		void generate_random_number(bytesNumber& entropy_input, bytesNumber& output_block, unsigned int num_bytes);
		void reset();
		
	private:
		// Internal States of the Randum Number Generator
		bytesNumber 	key;
		bytesNumber 	v;
		int32_t			reseed_counter;
		bool			instantiated;

		// Internal Parameters of the Random Number Generator
		unsigned int outlen_bytes;		// Number of bytes generated per encryption core invocation
		unsigned int keylen_bytes;		// Number of bytes used by the key
		unsigned int seedlen_bytes;		// Seed length in bytes (= outlen_bytes + keylen_bytes)
		int32_t reseed_counter_max;		// Maximum number of random numbers generated before reseeding is required
		primitive_core_e block_function_type;
			
		// Pointer to the selected block function.
		// unique_ptr automatically deletes the selected block when ctr_drbg is destroyed.
		unique_ptr<BlockFunction> block_function;
		
		// Main functions of the ctr_drbg
		void 	update		(const bytesNumber& provided_data);
		void 	instantiate	(const bytesNumber& personalization_string,	const bytesNumber& entropy_input);
		void 	reseed		(const bytesNumber& additional_input, 		const bytesNumber& entropy_input);
		void 	generate	(const bytesNumber& additional_input, 		const bytesNumber& entropy_input, bytesNumber& random_number_o, unsigned int num_bytes_out);

		// Helper functions for the ctr_drbg
		void	encrypt_engine	(unsigned int num_target_bytes, bytesNumber& output);
};
