// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "MersenneTwister.hpp"
#include "../Common/ParameterParser.hpp"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#define DEFAULT_LENGTH 32
#define DEFAULT_RESEED_PERIOD 256

using namespace std;

typedef struct {
	unsigned int LENGTH;
} MersenneTwisterConfig;

static MersenneTwisterConfig build_mersenne_twister_config(const ParameterParser& parameter_parser) {
	MersenneTwisterConfig config;
	int32_t LENGTH = parameter_parser.has("LENGTH") ? parameter_parser.get_int32("LENGTH", DEFAULT_LENGTH) : parameter_parser.get_int32("L", DEFAULT_LENGTH);

	// RESEED_PERIOD is accepted (and ignored) here only so that scripts/targets
	// sharing overrides with main_SIM.cpp do not fail on an unknown parameter.
	// It must NOT drive reseeding in this program: NIST SP 800-22 characterizes
	// a single long deterministic sequence from one seed. Periodically injecting
	// fresh entropy mid-stream repeatedly restarts MT19937's seeding recurrence,
	// which is detectably weaker than its steady-state output (a documented
	// MT19937 property), and was confirmed to fail every SP 800-22 p-value
	// uniformity check at 100 streams of 1e6 bits despite passing at smaller
	// sample sizes. See DEVELOPMENT.md for the full story if this changes again.
	int32_t reseed_period = parameter_parser.get_int32("RESEED_PERIOD", DEFAULT_RESEED_PERIOD);
	(void)reseed_period;

	if (LENGTH <= 0) {
		throw invalid_argument("ERROR: LENGTH must be greater than zero.");
	}
	if (reseed_period <= 0) {
		throw invalid_argument("ERROR: RESEED_PERIOD must be greater than zero.");
	}

	config.LENGTH = static_cast<unsigned int>(LENGTH);
	return config;
}

static bytesNumber seed_to_bytes(uint32_t seed) {
	bytesNumber seed_bytes(4);

	for (size_t byte_idx = 0; byte_idx < 4; byte_idx++) {
		seed_bytes[byte_idx] = static_cast<uint8_t>((seed >> (8 * byte_idx)) & 0xFF);
	}

	return seed_bytes;
}

int main(int argc, char* argv[]) {
	try {
		int num_bits_requested;

		if (argc < 3) {
			cerr << "ERROR: Usage <num_bits_requested> <output_bitstream_file> [+PARAM=VALUE ...]" << endl;
			return 1;
		}

		if (sscanf(argv[1], "%d", &num_bits_requested) != 1) {
			cerr << "ERROR: <num_bits_requested> must be a valid integer." << endl;
			return 1;
		}
		if (num_bits_requested < 0) {
			cerr << "ERROR: <num_bits_requested> cannot be negative." << endl;
			return 1;
		}

		const char* output_bitstream_file = argv[2];
		ParameterParser parameter_parser(argc, argv, 3);
		MersenneTwisterConfig config = build_mersenne_twister_config(parameter_parser);

		FILE* fp_output = fopen(output_bitstream_file, "w");
		if (fp_output == NULL) {
			cerr << "ERROR: Output bitstream file is not opened." << endl;
			return 1;
		}

		// Seed the MersenneTwister before generating the NIST bitstream.
		MersenneTwister mt(config.LENGTH);
		unsigned int seed = static_cast<unsigned int>(
			chrono::high_resolution_clock::now().time_since_epoch().count()
		);
		mt.reseed(seed_to_bytes(seed));

		int num_patterns = static_cast<int>(ceil(static_cast<double>(num_bits_requested) / config.LENGTH));

		for (int i = 0; i < num_patterns; i++) {
			bytesNumber generated_output = mt.generate_random_number();
			fprintf(fp_output, "%s\n", generated_output.toBinaryString().c_str());
		}

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
