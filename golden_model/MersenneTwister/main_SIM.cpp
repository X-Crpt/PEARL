// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "MersenneTwister.hpp"
#include "../Common/ParameterParser.hpp"
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#define DEFAULT_LENGTH 32
#define DEFAULT_RESEED_PERIOD 256

using namespace std;

typedef struct {
	unsigned int LENGTH;
	unsigned int reseed_period;
} MersenneTwisterConfig;

typedef struct {
	bool request_reseeding;
	bytesNumber seed;
} InputVectorRecord;

static MersenneTwisterConfig build_mersenne_twister_config(const ParameterParser& parameter_parser);
static int write_input_vector_file(const char* input_vector_file, int num_patterns, const MersenneTwisterConfig& config);
static int write_output_vector_file(const char* input_vector_file, const char* output_vector_file, const MersenneTwisterConfig& config);
static size_t bits_to_bytes_parameter(const string& name, int32_t bits);
static int read_input_vector_record(FILE* fd, InputVectorRecord& input_record, const MersenneTwisterConfig& config);
static void write_random_number(FILE* fd, const bytesNumber& random_number, unsigned int num_bits);

static MersenneTwisterConfig build_mersenne_twister_config(const ParameterParser& parameter_parser) {
	MersenneTwisterConfig config;
	int32_t LENGTH = parameter_parser.has("LENGTH") ? parameter_parser.get_int32("LENGTH", DEFAULT_LENGTH) : parameter_parser.get_int32("L", DEFAULT_LENGTH);
	int32_t reseed_period = parameter_parser.get_int32("RESEED_PERIOD", DEFAULT_RESEED_PERIOD);

	bits_to_bytes_parameter("LENGTH", LENGTH);
	if (reseed_period <= 0) {
		throw invalid_argument("ERROR: RESEED_PERIOD must be greater than zero.");
	}

	config.LENGTH = static_cast<unsigned int>(LENGTH);
	config.reseed_period = static_cast<unsigned int>(reseed_period);
	return config;
}

static int write_input_vector_record(FILE* fd, const InputVectorRecord& input_record) {
	if (fd == NULL) {
		return 0;
	}

	fprintf(fd, "%u %s\n", input_record.request_reseeding ? 1U : 0U, input_record.seed.toHexString().c_str());
	return 1;
}

static size_t bits_to_bytes_parameter(const string& name, int32_t bits) {
	if (bits <= 0) {
		throw invalid_argument("ERROR: " + name + " must be greater than zero.");
	}
	return static_cast<size_t>((bits + 7) / 8);
}

static void write_random_number(FILE* fd, const bytesNumber& random_number, unsigned int num_bits) {
	unsigned int num_hex_digits = (num_bits + 3) / 4;

	for (int digit_idx = static_cast<int>(num_hex_digits) - 1; digit_idx >= 0; digit_idx--) {
		unsigned int nibble = 0;

		for (unsigned int bit_idx = 0; bit_idx < 4; bit_idx++) {
			unsigned int output_bit_idx = static_cast<unsigned int>(digit_idx) * 4 + bit_idx;

			if (output_bit_idx < num_bits) {
				unsigned int byte_idx = output_bit_idx / 8;
				unsigned int byte_bit_idx = output_bit_idx % 8;
				nibble |= ((random_number[byte_idx] >> byte_bit_idx) & 1U) << bit_idx;
			}
		}

		fprintf(fd, "%x", nibble);
	}

	fprintf(fd, "\n");
}

static int read_input_vector_record(FILE* fd, InputVectorRecord& input_record, const MersenneTwisterConfig& config) {
	size_t seed_bytes = bits_to_bytes_parameter("LENGTH", config.LENGTH);
	vector<char> seed_hex((2 * seed_bytes) + 1);
	unsigned int request_reseeding;
	int scanned = fscanf(fd, "%u %s", &request_reseeding, seed_hex.data());
	if (scanned == EOF) {
		return 0;
	}
	if (scanned != 2) {
		return 0;
	}

	input_record.request_reseeding = (request_reseeding != 0);
	input_record.seed.fromHexString(seed_hex.data());
	return 1;
}

static int write_input_vector_file(const char* input_vector_file, int num_patterns, const MersenneTwisterConfig& config) {
	FILE* fp_input = fopen(input_vector_file, "w");
	if (fp_input == NULL) {
		throw runtime_error("ERROR: Input Vector file is not opened! Exiting the program ...");
	}

	mt19937_64 g_rng;
	unsigned long long seed_now = static_cast<unsigned long long>(chrono::high_resolution_clock::now().time_since_epoch().count());
	g_rng.seed(seed_now);

	size_t seed_bytes = bits_to_bytes_parameter("LENGTH", config.LENGTH);
	bytesNumber current_seed(seed_bytes);
	current_seed.resetValue();
	for (int i = 0; i < num_patterns; i++) {
		InputVectorRecord current_input;
		if ((i % config.reseed_period) == 0) {
			current_input.request_reseeding = 1;
			for (size_t current_byte = 0; current_byte < seed_bytes; current_byte++) {
				current_seed[current_byte] = static_cast<uint8_t>(g_rng() & 0xFF);
			}
		} else  {
			current_input.request_reseeding = 0;
		}
		current_input.seed = current_seed;
		
		if (!write_input_vector_record(fp_input, current_input)) {
			fclose(fp_input);
			throw runtime_error("ERROR: Failed to write input vector record: " + to_string(i + 1));
		}
	}

	if (fclose(fp_input) != 0) {
		throw runtime_error("ERROR: Input Vector unsuccessfully closed");
	}

	cout << "Input vector file written successfully" << endl;
	return 1;
}

static int write_output_vector_file(const char* input_vector_file, const char* output_vector_file, const MersenneTwisterConfig& config) {
	FILE* fp_output = fopen(output_vector_file, "w");
	if (fp_output == NULL) {
		throw runtime_error("ERROR: Output Vector file is not opened! Exiting the program ...");
	}

	FILE* fp_input = fopen(input_vector_file, "r");
	if (fp_input == NULL) {
		fclose(fp_output);
		throw runtime_error("ERROR: Input Vector file is not opened! Exiting the program ...");
	}

 	InputVectorRecord current_input;
 	MersenneTwister mt(config.LENGTH);
 	while (read_input_vector_record(fp_input, current_input, config)) {
		if (current_input.request_reseeding) {
			mt.reseed(current_input.seed);
		} else {
			bytesNumber random_number = mt.generate_random_number();
			write_random_number(fp_output, random_number, config.LENGTH);
		}		
 	}

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
		int num_patterns;
		char input_vector_file[1024];
		char output_vector_file[1024];

		if (argc < 4) {
			throw invalid_argument("ERROR: Usage <num_patterns> <input_vector_file> <output_vector_file> [+PARAM=VALUE ...]");
		}

		if (sscanf(argv[1], "%d", &num_patterns) != 1) {
			throw invalid_argument("ERROR: <num_patterns> must be a valid integer.");
		}
		if (num_patterns < 0) {
			throw invalid_argument("ERROR: <num_patterns> cannot be negative.");
		}
		snprintf(input_vector_file, sizeof(input_vector_file), "%s", argv[2]);
		snprintf(output_vector_file, sizeof(output_vector_file), "%s", argv[3]);

		ParameterParser parameter_parser(argc, argv, 4);
		MersenneTwisterConfig config = build_mersenne_twister_config(parameter_parser);

		write_input_vector_file(input_vector_file, num_patterns, config);
		if (!write_output_vector_file(input_vector_file, output_vector_file, config)) {
			throw runtime_error("ERROR: Failed to write output vector file.");
		}

		return 0;
	} catch (const exception& e) {
		cout << e.what() << endl;
		return 1;
	} catch (...) {
		cout << "ERROR: unknown exception" << endl;
		return 1;
	}
}
