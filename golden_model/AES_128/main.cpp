// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "AESBlockFunction.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/stat.h>
#include <sys/types.h>
#include <cryptopp/aes.h>
#include <cryptopp/secblock.h>

#define VECTOR_FOLDER_PATH "./SIM/AES_128/vectors/"
#define NUM_ROUNDS 10
#define PIPE_STATE_DEPTH (NUM_ROUNDS + 2)   // There is one pipeline stage for each AES round, plus one for inputs and one for outputs

typedef struct {
	const char* key_hex;
	const char* plaintext_hex;
	const char* ciphertext_hex;
} Aes128TestVector;

typedef struct {
	unsigned char valid_o;
	unsigned char busy_o;
	CryptoPP::byte output_o[CryptoPP::AES::BLOCKSIZE];
} OutputVectorRecord;

static const Aes128TestVector NIST_tests[] = {
	{"00000000000000000000000000000000", "f34481ec3cc627bacd5dc3fb08f273e6", "0336763e966d92595a567cc9ce537f5e"},
	{"00000000000000000000000000000000", "9798c4640bad75c7c3227db910174e72", "a9a1631bf4996954ebc093957b234589"},
	{"00000000000000000000000000000000", "96ab5c2ff612d9dfaae8c31f30c42168", "ff4f8391a6a40ca5b25d23bedd44a597"},
	{"00000000000000000000000000000000", "6a118a874519e64e9963798a503f1d35", "dc43be40be0e53712f7e2bf5ca707209"},
	{"00000000000000000000000000000000", "cb9fceec81286ca3e989bd979b0cb284", "92beedab1895a94faa69b632e5cc47ce"},
	{"00000000000000000000000000000000", "b26aeb1874e47ca8358ff22378f09144", "459264f4798f6a78bacb89c15ed3d601"},
	{"00000000000000000000000000000000", "58c8e00b2631686d54eab84b91f0aca1", "08a4e2efec8a8e3312ca7460b9040bbf"},
	// 
	{"00000000000000000000000000000000", "80000000000000000000000000000000", "3ad78e726c1ec02b7ebfe92b23d9ec34"},
	{"00000000000000000000000000000000", "c0000000000000000000000000000000", "aae5939c8efdf2f04e60b9fe7117b2c2"},
	{"00000000000000000000000000000000", "e0000000000000000000000000000000", "f031d4d74f5dcbf39daaf8ca3af6e527"},
	{"00000000000000000000000000000000", "f0000000000000000000000000000000", "96d9fd5cc4f07441727df0f33e401a36"},
	{"00000000000000000000000000000000", "f8000000000000000000000000000000", "30ccdb044646d7e1f3ccea3dca08b8c0"},
	{"00000000000000000000000000000000", "fc000000000000000000000000000000", "16ae4ce5042a67ee8e177b7c587ecc82"},
	{"00000000000000000000000000000000", "fe000000000000000000000000000000", "b6da0bb11a23855d9c5cb1b4c6412e0a"},
	{"00000000000000000000000000000000", "ff000000000000000000000000000000", "db4f1aa530967d6732ce4715eb0ee24b"},
	{"00000000000000000000000000000000", "ff800000000000000000000000000000", "a81738252621dd180a34f3455b4baa2f"},
	{"00000000000000000000000000000000", "ffc00000000000000000000000000000", "77e2b508db7fd89234caf7939ee5621a"},
	// 
	{"80000000000000000000000000000000", "00000000000000000000000000000000", "0edd33d3c621e546455bd8ba1418bec8"},
	{"c0000000000000000000000000000000", "00000000000000000000000000000000", "4bc3f883450c113c64ca42e1112a9e87"},
	{"e0000000000000000000000000000000", "00000000000000000000000000000000", "72a1da770f5d7ac4c9ef94d822affd97"},
	{"f0000000000000000000000000000000", "00000000000000000000000000000000", "970014d634e2b7650777e8e84d03ccd8"},
	{"f8000000000000000000000000000000", "00000000000000000000000000000000", "f17e79aed0db7e279e955b5f493875a7"},
	{"fc000000000000000000000000000000", "00000000000000000000000000000000", "9ed5a75136a940d0963da379db4af26a"},
	{"fe000000000000000000000000000000", "00000000000000000000000000000000", "c4295f83465c7755e8fa364bac6a7ea5"},
	{"ff000000000000000000000000000000", "00000000000000000000000000000000", "b1d758256b28fd850ad4944208cf1155"},
	{"ff800000000000000000000000000000", "00000000000000000000000000000000", "42ffb34c743de4d88ca38011c990890b"},
	{"ffc00000000000000000000000000000", "00000000000000000000000000000000", "9958f0ecea8b2172c0c1995f9182c0f3"},
};

#define NUM_NIST_TESTS (sizeof(NIST_tests) / sizeof(NIST_tests[0]))

static Aes128TestVector get_test_by_index(int idx) {
	return NIST_tests[(size_t)idx % NUM_NIST_TESTS];
}

static void print_output_result(
	FILE* fp_output,
	int valid_o,
	int busy_o,
	const CryptoPP::SecByteBlock& output_block
) {
	fprintf(fp_output, "%d %d ", valid_o, busy_o);
	for (int i = 0; i < CryptoPP::AES::BLOCKSIZE; i++) {
		fprintf(fp_output, "%02x", output_block[i]);
	}
	fprintf(fp_output, "\n");
}

static int write_input_vector_file(
	const char* input_vector_file,
	int num_patterns
) {
	FILE* fp_input = fopen(input_vector_file, "w");
	if (fp_input == NULL) {
		printf("ERROR: Input Vector file is not opened! Exiting the program ...\n");
		return 0;
	}

	// First cycle: force reset (gives deterministic startup to the RTL pipeline)
	fprintf(fp_input, "0 0 00000000000000000000000000000000 00000000000000000000000000000000\n");
	fprintf(fp_input, "0 0 00000000000000000000000000000000 00000000000000000000000000000000\n");

	for (int i = 0; i < num_patterns; i++) {
		Aes128TestVector test = get_test_by_index(i);
		// Format expected by data_maker: RST_n valid_i input_i key_i
		fprintf(fp_input, "1 1 %s %s\n", test.plaintext_hex, test.key_hex);
	}

	if (fclose(fp_input) != 0) {
		printf("ERROR: Input Vector unsuccessfully closed\n");
		return 0;
	}

	printf("💾 Input vector file written successfully\n");
	return 1;
}

static int write_output_vector_file(const char* input_vector_file, const char* output_vector_file) {
	// Open the Golden Model output file
	FILE* fp_output = fopen(output_vector_file, "w");
	if (fp_output == NULL) {
		printf("ERROR: Output Vector file is not opened! Exiting the program ...\n");
		return 0;
	}

	// Open the Input Vector file to read the patterns
	FILE* fp_input = fopen(input_vector_file, "r");
	if (fp_input == NULL) {
		printf("ERROR: Input Vector file is not opened! Exiting the program ...\n");
		return 0;
	}


	// Model of RTL pipeline registers/signals
	CryptoPP::SecByteBlock cipher_pipe[PIPE_STATE_DEPTH];
	int valid_pipe[PIPE_STATE_DEPTH] = {};
	AESBlockFunction aes_block_function(CryptoPP::AES::BLOCKSIZE);
	for (int i = 0; i < PIPE_STATE_DEPTH; i++) {
		cipher_pipe[i].CleanNew(CryptoPP::AES::BLOCKSIZE);	// Initialize the chiper input obeject to 0!
		memset(cipher_pipe[i].data(), 0, CryptoPP::AES::BLOCKSIZE);
	}

	while (1) {
		int rst_n_i = 1;
		int valid_i = 0;
		int inputs_end = 0;

		CryptoPP::SecByteBlock cipher_i	(CryptoPP::AES::BLOCKSIZE);	// Initialize the output data to be 16 bytes (128 bits)
		memset(cipher_i.data(), 0, CryptoPP::AES::BLOCKSIZE);
		
		
		
		// Read next input pattern if available from the input vector file
		char input_hex[33];
		char key_hex[33];
		int scan_status = fscanf(fp_input, "%d %d %32s %32s", &rst_n_i, &valid_i, input_hex, key_hex);
		if (scan_status != 4) {
			inputs_end = 1;
		}

		// If the valid signal is high (so the inputs are valid), perform the AES 128 encryption and get the cipher output
		if (valid_i) {
			bytesNumber input_block;
			bytesNumber key_block;
			input_block.fromHexString(input_hex);
			key_block.fromHexString(key_hex);

			bytesNumber cipher_block = aes_block_function.generate_block(key_block, input_block);
			cipher_i = cipher_block.toSecByteBlock();
		}

		// Compute busy/valid from current pipeline state
		int busy_o = 0;
		for (int i = 0; i < PIPE_STATE_DEPTH; i++) {
			busy_o |= valid_pipe[i];
		}
		int valid_o = valid_pipe[PIPE_STATE_DEPTH - 1];

		// Print the current output line
		print_output_result(fp_output, valid_o, busy_o, cipher_pipe[PIPE_STATE_DEPTH - 1]);

		// End the simulation if no more data are available and the pipeline is empty (not busy)
		if (inputs_end && !busy_o) {
			break;
		}

		if (!rst_n_i) {
			// If reset is low, clear the pipeline registers and valid bits
			for (int i = 0; i < PIPE_STATE_DEPTH; i++) {
				memset(cipher_pipe[i].data(), 0, CryptoPP::AES::BLOCKSIZE);
				valid_pipe[i] = 0;
			}
		} else {
			// Shift the pipeline registers and valid bits to the next stage only if pipeline is busy
			if (busy_o) {
				for (int i = PIPE_STATE_DEPTH - 1; i > 0; i--) {
					cipher_pipe[i] = cipher_pipe[i - 1];
					valid_pipe[i] = valid_pipe[i - 1];
				}
			}
			cipher_pipe[0] = cipher_i;
			valid_pipe[0] = valid_i;
		}
	}

	if (fclose(fp_output) != 0) {
		printf("ERROR: Output Vector unsuccessfully closed\n");
		return 0;
	}
	if (fclose(fp_input) != 0) {
		printf("ERROR: Input Vector unsuccessfully closed\n");
		return 0;
	}

	printf("💾 Output vector file written successfully\n");
	return 1;
}

int main(int argc, char* argv[]) {
	int num_patterns;
	char input_vector_file[1024];
	char output_vector_file[1024];

	// Parse command-line arguments
	if (argc != 4) {
		printf("ERROR: Usage <num_patterns> <input_vector_file> <output_vector_file>\n");
		return EXIT_FAILURE;
	}
	sscanf(argv[1], "%d", &num_patterns);										// Number of test patterns
	snprintf(input_vector_file, sizeof(input_vector_file), "%s", argv[2]);		// Input vector file path
	snprintf(output_vector_file, sizeof(output_vector_file), "%s", argv[3]);	// Output vector file path

	// Write the input vector file, basically the file that contains all the inputs to be fed to RTL and GoldeModel
	// designs, in order to stimulate them!
	if (!write_input_vector_file(input_vector_file, num_patterns)) {
		return EXIT_FAILURE;
	}

	// Write the output vector file, basically the file that contains all the outputs generated by the Golden Model,
	// which will be used by the Testbench as the reference for checking the correctness of the RTL design outputs!
	if (!write_output_vector_file(input_vector_file, output_vector_file)) {
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}
