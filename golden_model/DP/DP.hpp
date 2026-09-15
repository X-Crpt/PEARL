#pragma once

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "../Common/BlockFunction.hpp"
#include "../Common/PRNG.hpp"
#include "../Common/PrimitiveCore.hpp"
#include "../Common/bytesNumber.hpp"
#include <cstddef>
#include <memory>

using namespace std;

// Return codes for DP Golden Model operations
static constexpr int DP_USAGE_FAILURE	= 2;
static constexpr int DP_FAILURE			= 1;
static constexpr int DP_SUCCESS			= 0;

class DP : public PRNG {
	public:
		// Class Constructors
		DP	(
			const bytesNumber& A_in,
			const bytesNumber& B_in,
			size_t seed_bytes,
			primitive_core_e prg_type = PRIMITIVE_CORE_KECCAK,
			primitive_core_e extractor_type = PRIMITIVE_CORE_KECCAK
		);

		bytesNumber generate_random_number	(void) override;
		void reseed					(const bytesNumber& entropy_input) override;
		void reset					(void) override;
		
	private:
		// Internal States of the Randum Number Generator
		bytesNumber A, B, seed;
		bool isExtractionEven;
		bool isSeeded;

		// Type of units used inside this DP
		primitive_core_e	prg_type;
		primitive_core_e	extractor_type;
		unique_ptr<BlockFunction> prg_block;
		unique_ptr<BlockFunction> extractor_block;

		// Helper functions for the DP
		bytesNumber	extract	(const bytesNumber& memory_in) const;
		bytesNumber	prg		(const bytesNumber& seed_in) const;
};
