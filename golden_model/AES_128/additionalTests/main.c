// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "aes_step_utils.h"
// Keep this debug program one-command simple:
// `gcc main.c -o debug_main`
// by compiling helper functions in the same translation unit.
#include "aes_step_utils.cpp"

#define AES_BLOCK_BYTES 16
#define VECTOR_FOLDER_PATH "./SIM/AES_128/vectors/"
#define INPUT_VECTOR_FILE VECTOR_FOLDER_PATH "inputVect.txt"
#define OUTPUT_DEBUG_FILE VECTOR_FOLDER_PATH "outputVect_roundDebug.txt"
#define INPUT_VECTOR_FILE_LOCAL "../../vectors/inputVect.txt"
#define OUTPUT_DEBUG_FILE_LOCAL "../../vectors/outputVect_roundDebug.txt"

static int hex_nibble(char c) {
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
	if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
	return -1;
}

static int hex_to_bytes_16(const char* hex, uint8_t out[AES_BLOCK_BYTES]) {
	if ((int)strlen(hex) != 2 * AES_BLOCK_BYTES) return 0;

	for (int i = 0; i < AES_BLOCK_BYTES; i++) {
		int hi = hex_nibble(hex[2 * i]);
		int lo = hex_nibble(hex[2 * i + 1]);
		if (hi < 0 || lo < 0) return 0;
		out[i] = (uint8_t)((hi << 4) | lo);
	}

	return 1;
}

static void add_round_key_block(uint8_t state[16], const uint8_t round_key[16]) {
	uint8_t state_m[4][4];
	uint8_t key_m[4][4];

	unpack_state_col_major(state, state_m);
	unpack_state_col_major(round_key, key_m);

	add_round_key_state(state_m, key_m);
	pack_state_col_major(state_m, state);
}

static void sub_bytes_block(uint8_t state[16]) {
	uint8_t state_m[4][4];
	unpack_state_col_major(state, state_m);
	sub_bytes_state(state_m);
	pack_state_col_major(state_m, state);
}

static void shift_rows_block(uint8_t state[16]) {
	uint8_t state_m[4][4];
	unpack_state_col_major(state, state_m);
	shift_rows_state(state_m);
	pack_state_col_major(state_m, state);
}

static void mix_columns_block(uint8_t state[16]) {
	uint8_t state_m[4][4];
	unpack_state_col_major(state, state_m);
	mix_columns_state(state_m);
	pack_state_col_major(state_m, state);
}

static uint8_t sub_byte_with_utils(uint8_t b) {
	uint8_t tmp_state[4][4] = {{0}};
	tmp_state[0][0] = b;
	sub_bytes_state(tmp_state);
	return tmp_state[0][0];
}

static void next_round_key_128(
	const uint8_t round_key_i[16],
	int round_idx,
	uint8_t next_round_key_o[16]
) {
	static const uint8_t rcon[10] = {0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36};

	uint8_t w0[4], w1[4], w2[4], w3[4];
	uint8_t rot[4], sub[4], g[4];
	uint8_t w0n[4], w1n[4], w2n[4], w3n[4];

	memcpy(w0, &round_key_i[0], 4);
	memcpy(w1, &round_key_i[4], 4);
	memcpy(w2, &round_key_i[8], 4);
	memcpy(w3, &round_key_i[12], 4);

	rot[0] = w3[1];
	rot[1] = w3[2];
	rot[2] = w3[3];
	rot[3] = w3[0];

	sub[0] = sub_byte_with_utils(rot[0]);
	sub[1] = sub_byte_with_utils(rot[1]);
	sub[2] = sub_byte_with_utils(rot[2]);
	sub[3] = sub_byte_with_utils(rot[3]);

	g[0] = (uint8_t)(sub[0] ^ rcon[round_idx]);
	g[1] = sub[1];
	g[2] = sub[2];
	g[3] = sub[3];

	for (int i = 0; i < 4; i++) w0n[i] = (uint8_t)(w0[i] ^ g[i]);
	for (int i = 0; i < 4; i++) w1n[i] = (uint8_t)(w1[i] ^ w0n[i]);
	for (int i = 0; i < 4; i++) w2n[i] = (uint8_t)(w2[i] ^ w1n[i]);
	for (int i = 0; i < 4; i++) w3n[i] = (uint8_t)(w3[i] ^ w2n[i]);

	memcpy(&next_round_key_o[0],  w0n, 4);
	memcpy(&next_round_key_o[4],  w1n, 4);
	memcpy(&next_round_key_o[8],  w2n, 4);
	memcpy(&next_round_key_o[12], w3n, 4);
}

static void print_round_line(FILE* fp, int round_idx, const uint8_t key[16], const uint8_t state[16]) {
	fprintf(fp, "round_%02d | key=", round_idx);
	fprintf_hex(fp, key, AES_BLOCK_BYTES);
	fprintf(fp, " | state=");
	fprintf_hex(fp, state, AES_BLOCK_BYTES);
	fprintf(fp, "\n");
}

int main(int argc, char** argv) {
	const char* input_vector_file = INPUT_VECTOR_FILE;
	const char* output_debug_file = OUTPUT_DEBUG_FILE;
	int max_patterns = -1;

	// Optional argument:
	//   ./aes_round_debug <num_patterns>
	if (argc == 2) {
		sscanf(argv[1], "%d", &max_patterns);
	} else if (argc != 1) {
		printf("Usage: %s [num_patterns]\n", argv[0]);
		return EXIT_FAILURE;
	}

	FILE* fp_in = fopen(input_vector_file, "r");
	if (fp_in == NULL) {
		input_vector_file = INPUT_VECTOR_FILE_LOCAL;
		fp_in = fopen(input_vector_file, "r");
		if (fp_in == NULL) {
			printf("ERROR: cannot open input file: %s\n", input_vector_file);
			return EXIT_FAILURE;
		}
	}

	FILE* fp_out = fopen(output_debug_file, "w");
	if (fp_out == NULL) {
		output_debug_file = OUTPUT_DEBUG_FILE_LOCAL;
		fp_out = fopen(output_debug_file, "w");
		if (fp_out == NULL) {
			printf("ERROR: cannot open output file: %s\n", output_debug_file);
			fclose(fp_in);
			return EXIT_FAILURE;
		}
	}

	fprintf(fp_out, "============================================================\n");
	fprintf(fp_out, "AES-128 ROUND DEBUG REPORT (NO PIPELINE DELAY)\n");
	fprintf(fp_out, "Input format : RST_n valid_i input_i key_i\n");
	fprintf(fp_out, "Processed rows: only rows with valid_i = 1\n");
	fprintf(fp_out, "Round print  : key and state at end of each round\n");
	fprintf(fp_out, "============================================================\n\n");

	int rst_n_i = 0;
	int valid_i = 0;
	char input_hex[33];
	char key_hex[33];
	int data_idx = 0;

	while (fscanf(fp_in, "%d %d %32s %32s", &rst_n_i, &valid_i, input_hex, key_hex) == 4) {
		if (valid_i != 1) {
			continue;
		}

		if (max_patterns >= 0 && data_idx >= max_patterns) {
			break;
		}

		uint8_t state[16];
		uint8_t round_key[16];
		uint8_t next_key[16];

		if (!hex_to_bytes_16(input_hex, state)) {
			printf("ERROR: bad input hex at data_idx=%d\n", data_idx);
			fclose(fp_in);
			fclose(fp_out);
			return EXIT_FAILURE;
		}

		if (!hex_to_bytes_16(key_hex, round_key)) {
			printf("ERROR: bad key hex at data_idx=%d\n", data_idx);
			fclose(fp_in);
			fclose(fp_out);
			return EXIT_FAILURE;
		}

		fprintf(fp_out, "---------------- DATA %d ----------------\n", data_idx);
		fprintf(fp_out, "input = ");
		fprintf_hex(fp_out, state, AES_BLOCK_BYTES);
		fprintf(fp_out, "\nkey_0 = ");
		fprintf_hex(fp_out, round_key, AES_BLOCK_BYTES);
		fprintf(fp_out, "\n\n");

		// Round 0: initial AddRoundKey
		add_round_key_block(state, round_key);
		print_round_line(fp_out, 0, round_key, state);

		// Rounds 1..9: SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
		for (int round = 1; round <= 9; round++) {
			next_round_key_128(round_key, round - 1, next_key);
			memcpy(round_key, next_key, 16);

			sub_bytes_block(state);
			shift_rows_block(state);
			mix_columns_block(state);
			add_round_key_block(state, round_key);

			print_round_line(fp_out, round, round_key, state);
		}

		// Round 10 (final): SubBytes -> ShiftRows -> AddRoundKey
		next_round_key_128(round_key, 9, next_key);
		memcpy(round_key, next_key, 16);

		sub_bytes_block(state);
		shift_rows_block(state);
		add_round_key_block(state, round_key);

		print_round_line(fp_out, 10, round_key, state);

		fprintf(fp_out, "cipher = ");
		fprintf_hex(fp_out, state, AES_BLOCK_BYTES);
		fprintf(fp_out, "\n\n");

		data_idx++;
	}

	fprintf(fp_out, "Total valid data processed: %d\n", data_idx);

	fclose(fp_in);
	fclose(fp_out);

	printf("Debug file generated: %s (data processed: %d)\n", output_debug_file, data_idx);
	return EXIT_SUCCESS;
}
