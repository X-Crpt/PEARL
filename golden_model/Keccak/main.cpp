// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "Keccak.hpp"
#include <array>
#include <cstdint>
#include <iostream>
#include <stdexcept>

using namespace std;

static void run_main_c_test_vector() {
	static constexpr size_t STATE_WORDS = 50;
	static constexpr size_t STATE_BYTES = 200;
	array<uint32_t, STATE_WORDS> input_state = {};
	array<uint32_t, STATE_WORDS> expected_state = {};

	input_state[0] = 0x7369C667;
	input_state[1] = 0xEC4AFF51;
	input_state[2] = 0xABBACD29;
	input_state[3] = 0x00000010;
	input_state[31] = 0x80000000;

	expected_state[1] = 0xE1ADB0E2;
	expected_state[0] = 0xE7CB8356;
	expected_state[3] = 0xBB3F5FB8;
	expected_state[2] = 0x573A5BD7;
	expected_state[5] = 0xF7CA02A1;
	expected_state[4] = 0xE9784CC5;
	expected_state[7] = 0x6E54F256;
	expected_state[6] = 0x60A4C685;
	expected_state[9] = 0x77051F83;
	expected_state[8] = 0x243FCBAA;
	expected_state[11] = 0x6459DB0B;
	expected_state[10] = 0x4C063DD5;
	expected_state[13] = 0xE046DE71;
	expected_state[12] = 0xCB4B81C6;
	expected_state[15] = 0x94051793;
	expected_state[14] = 0xDB31F24C;
	expected_state[17] = 0xA13FC86C;
	expected_state[16] = 0xF16E32DD;
	expected_state[19] = 0xB962FC91;
	expected_state[18] = 0xB7737708;
	expected_state[21] = 0xD3CA2E7A;
	expected_state[20] = 0xFA27C801;
	expected_state[23] = 0x53C85108;
	expected_state[22] = 0xF72A3CCA;
	expected_state[25] = 0x73E732CD;
	expected_state[24] = 0xADF0E783;
	expected_state[27] = 0x8470BD54;
	expected_state[26] = 0xC4BDD1BF;
	expected_state[29] = 0xD10B916F;
	expected_state[28] = 0x7C8C1F77;
	expected_state[31] = 0x51129474;
	expected_state[30] = 0x440A2670;
	expected_state[33] = 0x3D77CB49;
	expected_state[32] = 0xE9960C44;
	expected_state[35] = 0xEC5001EB;
	expected_state[34] = 0xE4251E39;
	expected_state[37] = 0x77A0EEC5;
	expected_state[36] = 0xEA4FD653;
	expected_state[39] = 0xEBC86BD4;
	expected_state[38] = 0x7B6773E7;
	expected_state[41] = 0xE77DF6B0;
	expected_state[40] = 0x128FDC4B;
	expected_state[43] = 0x0DB0D48A;
	expected_state[42] = 0x02F1B12E;
	expected_state[45] = 0x241B344D;
	expected_state[44] = 0x0DC38AE5;
	expected_state[47] = 0xC3EE4E27;
	expected_state[46] = 0x532483D8;
	expected_state[49] = 0x0271BFE2;
	expected_state[48] = 0x84B1B424;

	bytesNumber input_bytes(STATE_BYTES);
	for (size_t word_idx = 0; word_idx < STATE_WORDS; word_idx++) {
		for (size_t byte_idx = 0; byte_idx < 4; byte_idx++) {
			input_bytes[(4 * word_idx) + byte_idx] = static_cast<uint8_t>((input_state[word_idx] >> (8 * byte_idx)) & 0xFF);
		}
	}

	bytesNumber output_bytes = Keccak::keccak_f1600(input_bytes);

	for (size_t i = 0; i < STATE_WORDS; i++) {
		uint32_t output_word = 0;
		for (size_t byte_idx = 0; byte_idx < 4; byte_idx++) {
			output_word |= static_cast<uint32_t>(output_bytes[(4 * i) + byte_idx]) << (8 * byte_idx);
		}

		if (output_word != expected_state[i]) {
			throw runtime_error("ERROR: Keccak output did not match the main.c test vector at word " + to_string(i));
		}
	}
}

int main() {
	try {
		run_main_c_test_vector();
		cout << "Keccak Golden Model test passed" << endl;
		return KECCAK_SUCCESS;
	} catch (const exception& e) {
		cout << e.what() << endl;
		return KECCAK_FAILURE;
	}
}
