// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "AESBlockFunction.hpp"
#include <cryptopp/aes.h>
#include <stdexcept>

using namespace CryptoPP;
using namespace std;

AESBlockFunction::AESBlockFunction(size_t output_bytes_in)
	: output_bytes(output_bytes_in) {
	if (output_bytes == 0) {
		throw invalid_argument("ERROR: AESBlockFunction output size cannot be 0 bytes");
	}
	if (output_bytes > AES::BLOCKSIZE) {
		throw invalid_argument("ERROR: AESBlockFunction cannot generate more than one AES block");
	}
}

bytesNumber AESBlockFunction::generate_block(
	const bytesNumber& key,
	const bytesNumber& input
) {
	AES::Encryption aes_enc;
	if (!aes_enc.IsValidKeyLength(key.size())) {
		throw invalid_argument("ERROR: Unsupported AES key length: " + to_string(key.size() * 8) + " bits.");
	}

	bytesNumber input_block = input;
	input_block.setSize(AES::BLOCKSIZE);

	SecByteBlock key_block = key.toSecByteBlock();
	SecByteBlock input_sec_block = input_block.toSecByteBlock();
	SecByteBlock output_sec_block(AES::BLOCKSIZE);

	aes_enc.SetKey(key_block.data(), key.size());
	aes_enc.ProcessBlock(input_sec_block.data(), output_sec_block.data());

	bytesNumber output_block;
	output_block.fromSecByteBlock(output_sec_block);
	return output_block.getSlice(output_bytes - 1, 0);
}
