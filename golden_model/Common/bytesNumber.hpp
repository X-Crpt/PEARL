// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Lightweight byte-oriented number container
//
// Data organization (downto-like convention):
// - Index 0           -> LSB byte
// - Index size()-1    -> MSB byte
//
// Example (4-byte number):
// - bytes[3] bytes[2] bytes[1] bytes[0]
// -   MSB        ...      ...      LSB
// ==============================================================================================

#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>
#include <string>
#include <cryptopp/secblock.h>

using byte = uint8_t;

class bytesNumber {
	public:
		// Constructors
		bytesNumber();
		bytesNumber(size_t num_bytes);

		// Public methods
		size_t size() const;											// Get the size of the number in bytes
		void setSize(size_t target_bytes);								// Set the size of the number in bytes (truncate or zero-extend on MSB side)
		void resetValue();												// Reset the value of the number to all zeros
		void zeroPad(size_t target_bytes);							
		bytesNumber getSlice(size_t MSB_byte, size_t LSB_byte) const;	
		void appendHighSide(const bytesNumber& other);					
		void appendLowSide(const bytesNumber& other);
		
		// Functions to convert this object into the object used by the CryptoPP library and vice versa
		// allowing simple usage of AES encryption defined in that library
		CryptoPP::SecByteBlock toSecByteBlock() const;
		void fromSecByteBlock(const CryptoPP::SecByteBlock& sec_block);

		// Functions to convert this object into a hexadecimal string and vice versa
		// Hex string convention: leftmost characters correspond to the MSB byte
		std::string toHexString() const;
		void fromHexString(const std::string& hex_string);

		// Function to convert this object into a binary string
		// Binary string convention: leftmost characters correspond to the MSB byte
		std::string toBinaryString() const;

		// Useful Operators
		byte& operator[]		(size_t idx);
		const byte& operator[]	(size_t idx) const;
		bytesNumber operator+	(unsigned int add_value) const;
		bytesNumber operator<<	(unsigned int shift_bytes) const;
		bytesNumber operator>>	(unsigned int shift_bytes) const;
		bytesNumber operator^	(const bytesNumber& other) const;
		
	private:
		char hexCharToValue(char c);	// Convert an hexadecimal character to its corresponding 4-bit value (0-15). Return -1 if the character is not a valid hexadecimal digit
		std::vector<byte> saved_bytes;	// The bytes of the number, organized from LSB to MSB
};
