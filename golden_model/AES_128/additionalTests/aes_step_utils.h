// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#ifndef AES_STEP_UTILS_H
#define AES_STEP_UTILS_H


// Mapping helpers: 128-bit flat block <-> AES state matrix [row][col] (column-major)
void unpack_state_col_major(const uint8_t in[16], uint8_t state[4][4]);
void pack_state_col_major(const uint8_t state[4][4], uint8_t out[16]);

// AES basic byte operations in GF(2^8)
uint8_t aes_add(uint8_t a, uint8_t b);
uint8_t aes_mult2(uint8_t b);
uint8_t aes_mult(uint8_t a, uint8_t m);

// AES state transformations
void sub_bytes_state(uint8_t state[4][4]);
void shift_rows_state(uint8_t state[4][4]);
void mix_columns_state(uint8_t state[4][4]);
void add_round_key_state(uint8_t state[4][4], const uint8_t round_key[4][4]);

// Print raw bytes as HEX (no newline)
void fprintf_hex(FILE* fp, const uint8_t* data, size_t len);

#endif
