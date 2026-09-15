// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "ctr_drbg.hpp"
#include "../Common/ParameterParser.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <sys/stat.h>
#include <sys/types.h>
#include <random>
#include <chrono>
#include <string>
#include <vector>

// Define the parameters of the ctr_drbg
#define DEFAULT_OUTLEN_BITS		128
#define DEFAULT_KEYLEN_BITS		128
#define DEFAULT_REQ_NUM_BITS 	128
#define DEFAULT_RESEED_CTR_BITS	8

typedef struct {
	int32_t				OUTLEN;
	int32_t				KEYLEN;
	int32_t				REQ_NUM_BITS;
	int32_t				RESEED_CTR_BITS;
	primitive_core_e	ENCRYPTION_CORE;
} ctr_drbg_SIM_Config;


typedef struct {
	bytesNumber entropy_input;
} InputVectorRecord;

typedef struct {
	bytesNumber output_o;
} OutputVectorRecord;

static ctr_drbg_SIM_Config	build_ctr_drbg_sim_config	(const ParameterParser& parameter_parser);
static size_t				get_seedlen_bytes			(const ctr_drbg_SIM_Config& config);


static int					write_input_vector_record	(FILE* fd, const InputVectorRecord& input_record);
static void					write_output_vector_record	(FILE* fd, const OutputVectorRecord& output_record);
static int					read_input_vector_record	(FILE* fd, InputVectorRecord& input_record, const ctr_drbg_SIM_Config& config);
static int32_t				get_reseed_counter_max		(const ctr_drbg_SIM_Config& config);
static int					write_input_vector_file		(const char* input_vector_file, int num_patterns, const ctr_drbg_SIM_Config& config);
static int 					write_output_vector_file	(const char* input_vector_file, const char* output_vector_file, const ctr_drbg_SIM_Config& config);

static int write_input_vector_record(FILE* fd, const InputVectorRecord& input_record) {
	if (fd == NULL) {
		return 0;
	}

	fprintf(fd, "%s\n", input_record.entropy_input.toHexString().c_str());

	return 1;
}

static void write_output_vector_record(FILE* fd, const OutputVectorRecord& output_record) {
	fprintf(fd, "%s\n", output_record.output_o.toHexString().c_str());
}

static size_t bits_to_bytes_parameter(const string& name, int32_t bits) {
	if ((bits <= 0) || ((bits % 8) != 0)) {
		throw invalid_argument("ERROR: " + name + " must be a positive multiple of 8.");
	}
	return static_cast<size_t>(bits / 8);
}

static ctr_drbg_SIM_Config build_ctr_drbg_sim_config(const ParameterParser& parameter_parser) {
	ctr_drbg_SIM_Config config;

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

static size_t get_seedlen_bytes(const ctr_drbg_SIM_Config& config) {
	return bits_to_bytes_parameter("KEYLEN", config.KEYLEN) + bits_to_bytes_parameter("OUTLEN", config.OUTLEN);
}

static int32_t get_reseed_counter_max(const ctr_drbg_SIM_Config& config) {
	return (1 << config.RESEED_CTR_BITS) - 1;
}

static int read_input_vector_record(FILE* fd, InputVectorRecord& input_record, const ctr_drbg_SIM_Config& config) {
	size_t seedlen_bytes = get_seedlen_bytes(config);
	vector<char> entropy_hex_string((2 * seedlen_bytes) + 1);

	// Read the input vector from the current line in the input vector file, and check for scanf success
	int scanned = fscanf(fd, "%s", entropy_hex_string.data());
	if (scanned == EOF) {
		return 0;
	}
	if (scanned != 1) {
		return 0;
	}

	// Transform the read string into bytesNumber format
	input_record.entropy_input.fromHexString(entropy_hex_string.data());

	// Return with success status
	return 1;
}

static int write_input_vector_file(const char* input_vector_file, int num_patterns, const ctr_drbg_SIM_Config& config) {
	FILE* fp_input = fopen(input_vector_file, "w");
	if (fp_input == NULL) {
		throw runtime_error("ERROR: Input Vector file is not opened! Exiting the program ...");
	}

	InputVectorRecord current_inputs;
	size_t seedlen_bytes = get_seedlen_bytes(config);

	// Request new random numbers, and provide entropy inputs at all cycles,
	// even if the ctr_drbg does not use them at all cycles
	std::mt19937_64 g_rng;	// Random number generator
	unsigned long long seed_now = static_cast<unsigned long long>(std::chrono::high_resolution_clock::now().time_since_epoch().count());
	g_rng.seed(seed_now);	// Seed the PRNG with a time-dependent seed

	for (int i = 0; i < num_patterns; i++) {
		current_inputs.entropy_input = bytesNumber(seedlen_bytes);
		current_inputs.entropy_input.resetValue();

		// Generate the entropy input for the current pattern and save it in the input vector file
		for (size_t current_byte = 0; current_byte < seedlen_bytes; current_byte++) {
			current_inputs.entropy_input[current_byte] = static_cast<uint8_t>(g_rng() & 0xFF);
		}
		if (!write_input_vector_record(fp_input, current_inputs)) {
			fclose(fp_input);
			throw runtime_error("ERROR: Failed to write input vector record: " + to_string(i + 1));
		}
	}

	// Close the input vector file
	if (fclose(fp_input) != 0) {
		throw runtime_error("ERROR: Input Vector unsuccessfully closed");
	}

	// Write success message
	cout << "Input vector file written successfully" << endl;
	return 1;
}

static int write_output_vector_file(const char* input_vector_file, const char* output_vector_file, const ctr_drbg_SIM_Config& config) {
	// Open output vector file (truncate)
	FILE* fp_output = fopen(output_vector_file, "w");
	if (fp_output == NULL) {
		throw runtime_error("ERROR: Output Vector file is not opened! Exiting the program ...");
	}

	// Open input vector file (read)
	FILE* fp_input = fopen(input_vector_file, "r");
	if (fp_input == NULL) {
		fclose(fp_output);
		throw runtime_error("ERROR: Input Vector file is not opened! Exiting the program ...");
	}

	size_t outlen_bytes = bits_to_bytes_parameter("OUTLEN", config.OUTLEN);
	size_t keylen_bytes = bits_to_bytes_parameter("KEYLEN", config.KEYLEN);
	size_t req_num_bytes = bits_to_bytes_parameter("REQ_NUM_BITS", config.REQ_NUM_BITS);

	ctr_drbg DUT(outlen_bytes, keylen_bytes, get_reseed_counter_max(config), config.ENCRYPTION_CORE);
	InputVectorRecord current_input_record;

	// Read all the input records, and for each of them generate the corresponding output
	while (read_input_vector_record(fp_input, current_input_record, config)) {
		bytesNumber generated_output(outlen_bytes);
		bytesNumber entropy_input = current_input_record.entropy_input;

		DUT.generate_random_number(entropy_input, generated_output, req_num_bytes);

		OutputVectorRecord current_output_record;
		current_output_record.output_o = generated_output;
		write_output_vector_record(fp_output, current_output_record);
	}

	// Close files
	if (fclose(fp_output) != 0) {
		fclose(fp_input);
		throw runtime_error("ERROR: Output Vector unsuccessfully closed");
	}
	if (fclose(fp_input) != 0) {
		throw runtime_error("ERROR: Input Vector unsuccessfully closed");
	}

	cout << "Output vector file written successfully" << endl;
	return 1;
}

int main(int argc, char* argv[]) {
	try {
		// Parse command-line arguments
		int num_patterns;
		char input_vector_file[1024];
		char output_vector_file[1024];
		if (argc < 4) {
			throw invalid_argument("ERROR: Usage <num_patterns> <input_vector_file> <output_vector_file> [+PARAM=VALUE ...]");
		}

		if (sscanf(argv[1], "%d", &num_patterns) != 1) {								// Number of test patterns
			throw invalid_argument("ERROR: <num_patterns> must be a valid integer.");
		}
		if (num_patterns < 0) {
			throw invalid_argument("ERROR: <num_patterns> cannot be negative.");
		}
		snprintf(input_vector_file,		sizeof(input_vector_file),	"%s",	argv[2]);		// Input vector file path
		snprintf(output_vector_file, 	sizeof(output_vector_file),	"%s",	argv[3]);	// Output vector file path

		// Parse Input over-ride parameters for the DUT
		ParameterParser parameter_parser(argc, argv, 4);
		ctr_drbg_SIM_Config config = build_ctr_drbg_sim_config(parameter_parser);

		// Write input vector file used to stimulate both RTL and Golden Model
		write_input_vector_file(input_vector_file, num_patterns, config);

		// Write output vector file generated by the Golden Model
		if (!write_output_vector_file(input_vector_file, output_vector_file, config)) {
			throw runtime_error("ERROR: Failed to write output vector file.");
		}

		return 0;
	} catch (const std::exception& e) {
		cout << e.what() << endl;
		return 1;
	} catch (...) {
		cout << "ERROR: unknown exception" << endl;
		return 1;
	}
}
