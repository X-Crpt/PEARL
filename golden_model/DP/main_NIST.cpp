// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "DP.hpp"
#include "../Common/ParameterParser.hpp"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

#define DEFAULT_LENGTH_STATE_BITS 32
#define DEFAULT_LENGTH_SEED_BITS 32
#define DEFAULT_A_INIT_HEX "0"
#define DEFAULT_B_INIT_HEX "0"
#define DEFAULT_START_ODD 0
#define DEFAULT_RESEED_PERIOD 256

typedef struct {
	size_t		memory_bytes;
	size_t		seed_bytes;
	int			reseed_period;
	bytesNumber	A_initial;
	bytesNumber	B_initial;
	int			start_odd;
	primitive_core_e	prg_type;
	primitive_core_e	extractor_type;
} DP_NIST_Config;

static DP_NIST_Config build_dp_nist_config(const ParameterParser& parameter_parser) {
	DP_NIST_Config config;
	int32_t length_state_bits = parameter_parser.get_int32("LENGTH_STATE", DEFAULT_LENGTH_STATE_BITS);
	int32_t length_seed_bits = parameter_parser.get_int32("LENGTH_SEED", DEFAULT_LENGTH_SEED_BITS);

	if ((length_state_bits <= 0) || ((length_state_bits % 8) != 0)) {
		throw invalid_argument("ERROR: LENGTH_STATE must be a positive multiple of 8.");
	}
	if ((length_seed_bits <= 0) || ((length_seed_bits % 8) != 0)) {
		throw invalid_argument("ERROR: LENGTH_SEED must be a positive multiple of 8.");
	}
	config.memory_bytes = static_cast<size_t>(length_state_bits / 8);
	config.seed_bytes = static_cast<size_t>(length_seed_bits / 8);
	config.reseed_period = parameter_parser.get_int32("RESEED_PERIOD", DEFAULT_RESEED_PERIOD);
	config.start_odd = parameter_parser.get_int32("START_ODD", DEFAULT_START_ODD);
	config.prg_type = static_cast<primitive_core_e>(parameter_parser.get_int32("PRG_CORE", PRIMITIVE_CORE_KECCAK));
	config.extractor_type = static_cast<primitive_core_e>(parameter_parser.get_int32("EXTRACTOR_CORE", PRIMITIVE_CORE_KECCAK));

	if (config.reseed_period <= 0) {
		throw invalid_argument("ERROR: RESEED_PERIOD must be greater than 0.");
	}
	if (config.start_odd != 0) {
		throw invalid_argument("ERROR: START_ODD=1 is not supported by the current DP golden model.");
	}
	if ((config.prg_type != PRIMITIVE_CORE_AES) && (config.prg_type != PRIMITIVE_CORE_KECCAK)) {
		throw invalid_argument("ERROR: Unsupported PRG_CORE value");
	}
	if ((config.extractor_type != PRIMITIVE_CORE_AES) && (config.extractor_type != PRIMITIVE_CORE_KECCAK)) {
		throw invalid_argument("ERROR: Unsupported EXTRACTOR_CORE value");
	}

	config.A_initial = parameter_parser.get_bytes("A_INIT", config.memory_bytes, DEFAULT_A_INIT_HEX);
	config.B_initial = parameter_parser.get_bytes("B_INIT", config.memory_bytes, DEFAULT_B_INIT_HEX);

	return config;
}

int main(int argc, char* argv[]) {
	try {
		int num_bits_requested;
		

		if (argc < 3) {
			cerr << "ERROR: Usage <num_bits_requested> <output_bitstream_file> [+PARAM=VALUE ...]" << endl;
			return 1;
		}

		// Check the correctness of the input command line arguments
		if (sscanf(argv[1], "%d", &num_bits_requested) != 1) {
			cerr << "ERROR: <num_bits_requested> must be a valid integer." << endl;
			return 1;
		}
		if (num_bits_requested < 0) {
			cerr << "ERROR: <num_bits_requested> cannot be negative." << endl;
			return 1;
		}

		// Save the Command Line argument of the Output File with a more readable name
		const char* output_bitstream_file = argv[2];
		ParameterParser parameter_parser(argc, argv, 3);
		DP_NIST_Config config = build_dp_nist_config(parameter_parser);

		// Open the Ouput File in Write Mode
		FILE* fp_output = fopen(output_bitstream_file, "w");
		if (fp_output == NULL) {
			cerr << "ERROR: Output bitstream file is not opened." << endl;
			return 1;
		}

		// Instantiate the DP
		bytesNumber A_initial = config.A_initial;
		bytesNumber B_initial = config.B_initial;

		DP DUT(A_initial, B_initial, config.seed_bytes, config.prg_type, config.extractor_type);

		// Generate a Random Seed, used to generate the reseed input for the DP
		mt19937_64 rng;
		unsigned long long seed_now = chrono::high_resolution_clock::now().time_since_epoch().count();
		rng.seed(seed_now);

		bytesNumber entropy_input(config.seed_bytes);
		for (size_t current_byte = 0; current_byte < config.seed_bytes; current_byte++) {
			entropy_input[current_byte] = static_cast<uint8_t>(rng() & 0xFF);
		}
		DUT.reseed(entropy_input);

		// Compute how many random number to request to DP, in order to generate enough bits for the
		// NIST Testing
		int num_patterns = static_cast<int>(ceil(static_cast<double>(num_bits_requested) / (config.seed_bytes * 8)));

		for (int i = 0; i < num_patterns; i++) {
			if ((i != 0) && ((i % config.reseed_period) == 0)) {
				for (size_t current_byte = 0; current_byte < config.seed_bytes; current_byte++) {
					entropy_input[current_byte] = static_cast<uint8_t>(rng() & 0xFF);
				}
				DUT.reseed(entropy_input);
			}

			// Generate the Random Number from the DP
			bytesNumber generated_output = DUT.generate_random_number();
			
			// Print the generated Random Number in the Ouput Vector
			fprintf(fp_output, "%s\n", generated_output.toBinaryString().c_str());
		}

		// Close the Ouput File
		if (fclose(fp_output) != 0) {
			throw runtime_error("ERROR: Output bitstream file unsuccessfully closed.");
		}

		cout << "NIST bitstream file written successfully" << endl;
		return 0;
	} catch (const exception& e) {
		cout << e.what() << endl;
		return 1;
	} catch (...) {
		cout << "ERROR: unknown exception" << endl;
		return 1;
	}
}
