// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "bytesNumber.hpp"
#include <stdexcept>
#include <algorithm>

bytesNumber::bytesNumber()
	: saved_bytes(0) {
}

bytesNumber::bytesNumber(size_t num_bytes)
	: saved_bytes(num_bytes) {
}

size_t bytesNumber::size() const {
	return saved_bytes.size();
}

void bytesNumber::setSize(size_t target_bytes) {
	// Resize the number preserving LSB bytes:
	// - if target size is larger, append zeros on MSB side
	// - if target size is smaller, truncate MSB bytes
	saved_bytes.resize(target_bytes, 0);
}

void bytesNumber::resetValue() {
	// Reset the current number by setting all currently allocated bytes to zero
	for (size_t i = 0; i < saved_bytes.size(); i++) {
		saved_bytes[i] = 0;
	}
}

byte& bytesNumber::operator[](size_t idx) {
	if (idx >= saved_bytes.size()) {
		throw std::out_of_range("bytesNumber index out of range");
	}
	return saved_bytes[idx];
}

const byte& bytesNumber::operator[](size_t idx) const {
	if (idx >= saved_bytes.size()) {
		throw std::out_of_range("bytesNumber index out of range");
	}
	return saved_bytes[idx];
}

bytesNumber bytesNumber::operator+(unsigned int add_value) const {
	bytesNumber result = *this;
	
	// Add on one byte at a time starting from the LSB side and propagate the carry toward MSB
	// Overflow is naturally discarded in this way
	// Stop the propagation early if there is no more carry and no more value to add
	size_t carry = static_cast<size_t>(add_value);
	size_t idx = 0;
	while ((carry != 0) && (idx < result.size())) {
		size_t sum = static_cast<size_t>(result[idx]) + (carry & static_cast<size_t>(0xFF));
		result[idx] = static_cast<byte>(sum & static_cast<size_t>(0xFF));
		carry = (carry >> 8) + (sum >> 8);
		
		// Prepare the data for the next cycle
		idx++;
	}

	return result;
}

bytesNumber bytesNumber::operator<<(unsigned int shift_bytes) const {
	// If the shift amount is zero, return the same number
	if (shift_bytes == 0) {
		return *this;
	}

	// Left shift by bytes in fixed size: add zeros on LSB side and drop overflowing MSB bytes
	bytesNumber result(this->size());
	for (size_t i = 0; (i < this->size()) && ((i + shift_bytes) < this->size()); i++) {
		result[i + shift_bytes] = (*this)[i];
	}
	return result;
}

bytesNumber bytesNumber::operator>>(unsigned int shift_bytes) const {
	// If the shift amount is zero, return the same number
	if (shift_bytes == 0) {
		return *this;
	}

	// If we shift more than the available bytes, the number becomes all zeros in the same size
	if (shift_bytes >= this->size()) {
		return bytesNumber(this->size());
	}

	// Right shift by bytes in fixed size: drop LSB bytes and fill MSB side with zeros
	bytesNumber result(this->size());
	for (size_t i = 0; (i + shift_bytes) < this->size(); i++) {
		result[i] = (*this)[i + shift_bytes];
	}
	return result;
}

bytesNumber bytesNumber::operator^(const bytesNumber& other) const {
	// The output size of the XOR operation is the maximum size of the two input numbers
	size_t output_size = std::max(this->size(), other.size());

	bytesNumber result(output_size);
	for (size_t i = 0; i < output_size; i++) {
		// XOR aligned on the LSB side
		byte self_byte = (i < this->size()) ? (*this)[i] : 0;
		byte other_byte = (i < other.size()) ? other[i] : 0;
		result[i] = self_byte ^ other_byte;
	}
	return result;
}

CryptoPP::SecByteBlock bytesNumber::toSecByteBlock() const {
	// Convert from internal LSB->MSB organization to SecByteBlock MSB->LSB organization
	CryptoPP::SecByteBlock sec_block(this->size());
	for (size_t i = 0; i < this->size(); i++) {
		sec_block[this->size() - 1 - i] = (*this)[i];
	}
	return sec_block;
}

void bytesNumber::fromSecByteBlock(const CryptoPP::SecByteBlock& sec_block) {
	// Convert from SecByteBlock MSB->LSB organization to internal LSB->MSB organization
	saved_bytes.resize(sec_block.size());
	for (size_t i = 0; i < sec_block.size(); i++) {
		(*this)[i] = sec_block[sec_block.size() - 1 - i];
	}
}

std::string bytesNumber::toHexString() const {
	// Constant declaring all the hexadecimal digits
	static const char HEX_DIGITS[] = "0123456789abcdef";

	size_t num_bytes = this->size();
	std::string hex_string;
	hex_string.resize(num_bytes * 2);	// String should have exactly 2 characters per byte
	for (size_t i = 0; i < this->size(); i++) {
		// Go from MSB to LSB bytes
		byte current_byte = saved_bytes[num_bytes - 1 - i];
		
		// In the current byte, first save the 4 leftmost bits, and then the 4 rightmost bits 
		hex_string[2 * i] 		= HEX_DIGITS[(current_byte >> 4) & 0x0F];
		hex_string[2 * i + 1] 	= HEX_DIGITS[current_byte & 0x0F];
	}
	return hex_string;
}

std::string bytesNumber::toBinaryString() const {
	size_t num_bytes = this->size();
	std::string binary_string;
	binary_string.resize(num_bytes * 8);

	// Cycle thorugh all the Bytes
	for (size_t i = 0; i < num_bytes; i++) {
		// Go from MSB to LSB bytes
		byte current_byte = saved_bytes[num_bytes - 1 - i];

		for (size_t bit_idx = 0; bit_idx < 8; bit_idx++) {
			byte current_bit = (current_byte >> (7 - bit_idx)) & 0x01;
			binary_string[(8 * i) + bit_idx] = current_bit ? '1' : '0';
		}
	}

	return binary_string;
}

void bytesNumber::fromHexString(const std::string& hex_string) {
	// Define the target number of bytes, and resize the internal storage to accommodate those bytes.
	// If the input string has an odd number of characters, the first hex digit is treated as:
	// - the low nibble of the MSB byte
	// - with an implicit leading 0 nibble
	size_t num_bytes = (hex_string.size() / 2) + (hex_string.size() % 2);
	this->setSize(num_bytes);

	// If the input is empty, we are done
	if (hex_string.empty()) {
		return;
	}

	// Parse the hexadecimal string from left to right (MSB to LSB)
	size_t string_idx = 0;
	size_t output_idx = num_bytes - 1;

	// Odd-length input: handle the first single nibble with an implicit leading zero
	if ((hex_string.size() % 2) != 0) {
		char low_char = hexCharToValue(hex_string[0]);
		saved_bytes[output_idx] = static_cast<byte>(low_char);
		string_idx = 1;
		if (output_idx > 0) {
			output_idx--;
		}
	}

	// Parse the remaining complete bytes
	while (string_idx < hex_string.size()) {
		char high_char = hexCharToValue(hex_string[string_idx]);		// Leftmost character of the current byte
		char low_char = hexCharToValue(hex_string[string_idx + 1]);	// Rightmost character of the current byte

		// Save the byte
		saved_bytes[output_idx] = static_cast<byte>((high_char << 4) | low_char);
		string_idx += 2;
		if (output_idx > 0) {
			output_idx--;
		}
	}
}

char bytesNumber::hexCharToValue(char c) {
	if (c >= '0' && c <= '9') {
		return c - '0';
	}
	if (c >= 'a' && c <= 'f') {
		return 10 + (c - 'a');
	}
	if (c >= 'A' && c <= 'F') {
		return 10 + (c - 'A');
	}

	// If the character is not a valid hexadecimal digit, throw an error
	throw std::invalid_argument("The provided character is not a valid hexadecimal digit: " + std::string(1, c));
}


void bytesNumber::zeroPad(size_t target_bytes) {
	if (saved_bytes.size() >= target_bytes) {
		return;
	}

	// Increase the size while keeping the same numeric value by padding zeros on the MSB side
	std::vector<byte> padded(target_bytes);
	for (size_t i = 0; i < saved_bytes.size(); i++) {
		padded[i] = saved_bytes[i];
	}

	saved_bytes = padded;
}

bytesNumber bytesNumber::getSlice(size_t MSB_byte, size_t LSB_byte) const {
	// If one of the slice bounds is outside the current number, return with an error
	if (LSB_byte >= this->size()) {
		throw std::out_of_range("bytesNumber getSlice LSB index out of range");
	}
	if (MSB_byte >= this->size()) {
		throw std::out_of_range("bytesNumber getSlice MSB index out of range");
	}

	// If the requested byte range is invalid for [MSB:LSB], return an empty number
	if (MSB_byte < LSB_byte) {
		throw std::invalid_argument("bytesNumber getSlice invalid range: MSB_byte < LSB_byte");
	}
	size_t slice_bytes = (MSB_byte - LSB_byte) + 1;

	// Generate a new number with the requested slice size
	bytesNumber result(slice_bytes);
	for (size_t i = 0; i < slice_bytes; i++) {
		result[i] = (*this)[LSB_byte + i];
	}

	// Return the extracted slice
	return result;
}

void bytesNumber::appendHighSide(const bytesNumber& other) {
	// If the number to append is empty, do nothing
	if (other.size() == 0) {
		return;
	}

	// Generate a new number, with the size of the final appended number
	bytesNumber appended(other.size() + this->size());

	// On the LSB side, copy the current number
	for (size_t i = 0; i < this->size(); i++) {
		appended[i] = (*this)[i];
	}
	// After the current number, copy the appended number on the MSB side
	for (size_t i = 0; i < other.size(); i++) {
		appended[this->size() + i] = other[i];
	}

	// Update the current number with the new appended number
	*this = appended;
}

void bytesNumber::appendLowSide(const bytesNumber& other) {
	// If the number to append is empty, do nothing
	if (other.size() == 0) {
		return;
	}

	// Generate a new number, with the size of the final appended number
	bytesNumber appended(this->size() + other.size());

	// On the LSB side, copy the number to append
	for (size_t i = 0; i < other.size(); i++) {
		appended[i] = other[i];
	}
	// After the appended number, copy the current number on the MSB side
	for (size_t i = 0; i < this->size(); i++) {
		appended[other.size() + i] = (*this)[i];
	}

	// Update the current number with the new appended number
	*this = appended;
}
