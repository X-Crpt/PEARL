// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "ctr_drbg.hpp"
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

#define DEFAULT_OUTLEN_BITS 128
#define DEFAULT_KEYLEN_BITS 128
#define DEFAULT_REQ_NUM_BITS 128
#define DEFAULT_RESEED_CTR_BITS 8

typedef struct {
	int32_t		OUTLEN;
	int32_t		KEYLEN;
	int32_t		REQ_NUM_BITS;
	int32_t		RESEED_CTR_BITS;
	primitive_core_e	ENCRYPTION_CORE;
} ctr_drbg_NIST_Config;

static size_t bits_to_bytes_parameter(const string& name, int32_t bits) {
	if ((bits <= 0) || ((bits % 8) != 0)) {
		throw invalid_argument("ERROR: " + name + " must be a positive multiple of 8.");
	}
	return static_cast<size_t>(bits / 8);
}

static ctr_drbg_NIST_Config build_ctr_drbg_nist_config(const ParameterParser& parameter_parser) {
	ctr_drbg_NIST_Config config;

	config.OUTLEN			= parameter_parser.get_int32("OUTLEN", 			DEFAULT_OUTLEN_BITS);
	config.KEYLEN			= parameter_parser.get_int32("KEYLEN", 			DEFAULT_KEYLEN_BITS);
	config.REQ_NUM_BITS		= parameter_parser.get_int32("REQ_NUM_BITS", 	DEFAULT_REQ_NUM_BITS);
	config.RESEED_CTR_BITS	= parameter_parser.get_int32("RESEED_CTR_BITS", DEFAULT_RESEED_CTR_BITS);
	config.ENCRYPTION_CORE	= static_cast<primitive_core_e>(parameter_parser.get_int32("ENCRYPTION_CORE", PRIMITIVE_CORE_AES));

	bits_to_bytes_parameter("OUTLEN", config.OUTLEN);
	bits_to_bytes_parameter("KEYLEN", config.KEYLEN);
	bits_to_bytes_parameter("REQ_NUM_BITS", config.REQ_NUM_BITS);
	if (config.RESEED_CTR_BITS <= 0) {
		throw invalid_argument("ERROR: RESEED_CTR_BITS must be greater than 0.");
	}
	if ((config.ENCRYPTION_CORE != PRIMITIVE_CORE_AES) && (config.ENCRYPTION_CORE != PRIMITIVE_CORE_KECCAK)) {
		throw invalid_argument("ERROR: Unsupported ENCRYPTION_CORE value");
	}

	return config;
}

static int32_t get_reseed_counter_max(const ctr_drbg_NIST_Config& config) {
	return (1 << config.RESEED_CTR_BITS) - 1;
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
		ctr_drbg_NIST_Config config = build_ctr_drbg_nist_config(parameter_parser);

		// Open the Ouput File in Write Mode
		FILE* fp_output = fopen(output_bitstream_file, "w");
		if (fp_output == NULL) {
			cerr << "ERROR: Output bitstream file is not opened." << endl;
			return 1;
		}

		// Instantiate the ctr_drbg
		size_t outlen_bytes = bits_to_bytes_parameter("OUTLEN", config.OUTLEN);
		size_t keylen_bytes = bits_to_bytes_parameter("KEYLEN", config.KEYLEN);
		size_t req_num_bytes = bits_to_bytes_parameter("REQ_NUM_BITS", config.REQ_NUM_BITS);
		size_t seedlen_bytes = keylen_bytes + outlen_bytes;

		ctr_drbg DUT(outlen_bytes, keylen_bytes, get_reseed_counter_max(config), config.ENCRYPTION_CORE);

		// Generate a Random Seed, used to generate the TRNG input (entropy) for the ctr_drbg
		mt19937_64 rng;
		unsigned long long seed_now = chrono::high_resolution_clock::now().time_since_epoch().count();
		rng.seed(seed_now);

		// Compute how many random number to request to ctr_drbg, in order to generate enough bits for the
		// NIST Testing
		int num_patterns = static_cast<int>(ceil(static_cast<double>(num_bits_requested) / (req_num_bytes * 8)));

		for (int i = 0; i < num_patterns; i++) {
			// Generate the entropy input for the current ctr_drbg request
			bytesNumber entropy_input(seedlen_bytes);
			for (size_t current_byte = 0; current_byte < seedlen_bytes; current_byte++) {
				entropy_input[current_byte] = static_cast<uint8_t>(rng() & 0xFF);
			}

			// Generate the Random Number from the ctr_drbg
			bytesNumber generated_output(outlen_bytes);
			DUT.generate_random_number(entropy_input, generated_output, req_num_bytes);
			
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
