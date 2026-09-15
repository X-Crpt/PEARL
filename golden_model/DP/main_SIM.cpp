// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "DP.hpp"
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
} DP_SIM_Config;

typedef struct {
	bool request_reseed;
	bytesNumber seed;
} InputVectorRecord;

typedef struct {
	bytesNumber output_o;
} OutputVectorRecord;

static int 	write_input_vector_record	(FILE* fd, const InputVectorRecord& input_record);
static void	write_output_vector_record	(FILE* fd, const OutputVectorRecord& output_record);
static int	read_input_vector_record	(FILE* fd, InputVectorRecord& input_record);
static DP_SIM_Config build_dp_sim_config(const ParameterParser& parameter_parser);
static int	write_input_vector_file		(const char* input_vector_file, int num_patterns, const DP_SIM_Config& config);
static int	write_output_vector_file	(const char* input_vector_file, const char* output_vector_file, const DP_SIM_Config& config);

static int write_input_vector_record(FILE* fd, const InputVectorRecord& input_record) {
	if (fd == NULL) {
		return 0;
	}

	fprintf(fd, "%u %s\n", input_record.request_reseed ? 1 : 0, input_record.seed.toHexString().c_str());

	return 1;
}

static void write_output_vector_record(FILE* fd, const OutputVectorRecord& output_record) {
	fprintf(fd, "%s\n", output_record.output_o.toHexString().c_str());
}

static DP_SIM_Config build_dp_sim_config(const ParameterParser& parameter_parser) {
	DP_SIM_Config config;
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

static int read_input_vector_record(FILE* fd, InputVectorRecord& input_record) {
	unsigned int request_reseed;
	char seed_hex_string[4096];

	// Read the input vector from the current line in the input vector file, and check for scanf success
	int scanned = fscanf(fd, "%u %s", &request_reseed, seed_hex_string);
	if (scanned == EOF) {
		return 0;
	}
	if (scanned != 2) {
		return 0;
	}

	// Transform the read string into bytesNumber format
	input_record.request_reseed = (request_reseed != 0);
	input_record.seed.fromHexString(seed_hex_string);

	// Return with success status
	return 1;
}

static int write_input_vector_file(const char* input_vector_file, int num_patterns, const DP_SIM_Config& config) {
	FILE* fp_input = fopen(input_vector_file, "w");
	if (fp_input == NULL) {
		throw runtime_error("ERROR: Input Vector file is not opened! Exiting the program ...");
	}

	InputVectorRecord current_inputs;

	// Provide a random seed at every cycle, but request a reseed only every
	// configured reseed period.
	std::mt19937_64 g_rng;	// Random number generator
	unsigned long long seed_now = static_cast<unsigned long long>(std::chrono::high_resolution_clock::now().time_since_epoch().count());
	g_rng.seed(seed_now);	// Seed the PRNG with a time-dependent seed

	for (int i = 0; i < num_patterns; i++) {
		current_inputs.request_reseed = ((i % config.reseed_period) == 0);
		current_inputs.seed = bytesNumber(config.seed_bytes);
		current_inputs.seed.resetValue();

		// Generate the seed value for the current pattern and save it in the input vector file
		for (size_t current_byte = 0; current_byte < config.seed_bytes; current_byte++) {
			current_inputs.seed[current_byte] = static_cast<uint8_t>(g_rng() & 0xFF);
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

static int write_output_vector_file(const char* input_vector_file, const char* output_vector_file, const DP_SIM_Config& config) {
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

	DP DUT(config.A_initial, config.B_initial, config.seed_bytes, config.prg_type, config.extractor_type);
	InputVectorRecord current_input_record;

	// Read all the input records, and for each of them generate the corresponding output
	while (read_input_vector_record(fp_input, current_input_record)) {
		if (current_input_record.request_reseed) {
			DUT.reseed(current_input_record.seed);
			continue;
		}

		OutputVectorRecord current_output_record;
		current_output_record.output_o = DUT.generate_random_number();
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

		ParameterParser parameter_parser(argc, argv, 4);
		DP_SIM_Config config = build_dp_sim_config(parameter_parser);

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
