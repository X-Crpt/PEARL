// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "BlockFunction.hpp"
#include <stdexcept>

bytesNumber BlockFunction::generate_block(const bytesNumber& input) {
	(void)input;
	throw std::logic_error("ERROR: This block function does not support single-input calls");
}

bytesNumber BlockFunction::generate_block(const bytesNumber& key, const bytesNumber& input) {
	(void)key;
	(void)input;
	throw std::logic_error("ERROR: This block function does not support keyed-input calls");
}
