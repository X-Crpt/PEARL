// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "ctr_drbg.hpp"
#include "../AES_128/AESBlockFunction.hpp"
#include "../Keccak/Keccak.hpp"
#include <memory>
#include <stdexcept>

ctr_drbg::ctr_drbg(
	size_t outlen_bytes_in,
	size_t keylen_bytes_in,
	int32_t reseed_counter_max_in,
	primitive_core_e block_function_type
)
	: key(keylen_bytes_in),
	  v(outlen_bytes_in) {
	if (reseed_counter_max_in <= 0) {
		throw invalid_argument("ERROR: reseed_counter_max cannot be negative or 0");
	}

	
	// This unit is not already been instantiated
	instantiated = 0;
	
	// Save the input parameters inside the object of the ctr_drbg
	outlen_bytes 		= outlen_bytes_in;
	keylen_bytes 		= keylen_bytes_in;
	seedlen_bytes 		= outlen_bytes + keylen_bytes;
	this->block_function_type = block_function_type;

	// Select the block function used by the CTR_DRBG.
	// After this point the algorithm does not need to know if the block is AES or Keccak.
	switch (block_function_type) {
		case PRIMITIVE_CORE_AES:
			block_function = make_unique<AESBlockFunction>(outlen_bytes);
			break;

		case PRIMITIVE_CORE_KECCAK:
			block_function = make_unique<Keccak>(outlen_bytes);
			break;

		default:
			throw invalid_argument("ERROR: Unsupported CTR_DRBG block function");
	}
		
	// Initialize the counter of generated random numbers
	reseed_counter		= 0;					// Reset the number of generated random numbers since last reseed
	reseed_counter_max	= reseed_counter_max_in;	// Set the maximum number of random numbers generated before reseeding
	
	// Initialize the internal states of the ctr_drbg Golden Model to all zeros
	key.resetValue();
	v.resetValue();
}

void ctr_drbg::generate_random_number(bytesNumber& entropy_input, bytesNumber& random_number_o, unsigned int num_bytes_out) {
	// Check if the unit is already instantiated
	if (!instantiated) {
		bytesNumber personalization_string(0);
		instantiate(personalization_string, entropy_input);
	}

	// Generate the next random number, and return the status of the generation (success or failure)
	bytesNumber additional_input(0);	// No additional input in this call
	generate(additional_input, entropy_input, random_number_o, num_bytes_out);
}

void ctr_drbg::reset() {
	// Reset the internal states of the ctr_drbg Golden Model to all zeros
	key.resetValue();
	v.resetValue();
	reseed_counter = 0;
	instantiated = 0;
}

void ctr_drbg::update (const bytesNumber& provided_data) {
	// Generate the random number needed for updating the internal state of ctr_drbg
	bytesNumber temp;
	encrypt_engine(seedlen_bytes, temp);	// Generate the Random Number
	temp = temp ^ provided_data;			// XOR the generated random number with the Provided Data

	// Update the state of the ctr_drbg with the generated random number
	key	= temp.getSlice (seedlen_bytes-1, seedlen_bytes-keylen_bytes);	// Key is: leftmost (keylen_bytes) bytes of the generated buffer
	v 	= temp.getSlice (outlen_bytes-1, 0);								// V is: leftmost (outlen_bytes) bytes of the generated buffer
}

void ctr_drbg::instantiate(const bytesNumber& personalization_string, const bytesNumber& entropy_input) {
	// Check the size of the personalization string, and if it is greater than seedlen, return with an error
	unsigned int personalization_string_bytes = personalization_string.size();
	if (personalization_string_bytes > seedlen_bytes) {
		throw invalid_argument(
			"ERROR: The personalization string is too long. Maximum allowed size is " +
			to_string(seedlen_bytes * 8) + " bits."
		);
	}

	// If the personalization string is shorter than seedlen, pad it with zeros until it 
	// reaches the seedlen size
	bytesNumber seed = personalization_string;
	seed.zeroPad(seedlen_bytes);

	// Generate the inital seed of the ctr_drbg by XORing the entropy_input and the personalization string
	seed = seed ^ entropy_input;

	// Initialize the key and V values of the ctr_drbg Golden Model with 0 values
	key.resetValue();
	v.resetValue();

	// Update the internal states of the ctr_drbg Golden Model using the padded personalization string
	update(seed);

	// Set the counter of generated random numbers since last reseed to 1
	reseed_counter = 1;	

	// Set the unit as instantiated
	instantiated = 1;
}

void ctr_drbg::reseed(const bytesNumber& additional_input, const bytesNumber& entropy_input) {

	// Pad the Additional Input with zeros to the seedlen size
	bytesNumber additional_input_internal = additional_input;
	additional_input_internal.zeroPad(seedlen_bytes);

	// XOR together the Additional Input and the Entropy Input to generate the seed for reseeding
	bytesNumber seed = additional_input ^ entropy_input;

	// Update the internal states of the ctr_drbg using the generated seed
	update(seed);

	// Reset the counter of generated random numbers since last reseed to 0
	reseed_counter = 1;
}

void ctr_drbg::generate (const bytesNumber& additional_input, const bytesNumber& entropy_input, bytesNumber& random_number_o, unsigned int num_bytes_out) {
	// Check if the inputs have expected lengths
	if (additional_input.size() > seedlen_bytes) {
		throw invalid_argument(
			"ERROR: The additional input is too long. Maximum allowed size is " +
			to_string(seedlen_bytes * 8) + " bits."
		);
	}

	if (entropy_input.size() > seedlen_bytes) {
		throw invalid_argument(
			"ERROR: The entrpèy input is too long. Maximum allowed size is " +
			to_string(seedlen_bytes * 8) + " bits."
		);
	}
	
	// If the too much numbers was generated since the last reseed, reseed the ctr_drbg again
	if (reseed_counter > reseed_counter_max) {
		reseed(additional_input, entropy_input);
	}

	// If there are some additional input, use them to Update the Internal States of ctr_drbg before 
	// generating the random output
	if (additional_input.size() != 0) {
		// If the additional input is shorter than seedlen, pad it with zeros to the wanted length
		bytesNumber additional_input_internal = additional_input;
		additional_input_internal.zeroPad(seedlen_bytes);
		
		// Update the internal states of the ctr_drbg using the additional input
		update(additional_input_internal);
	}

	// Generate the random output using the current internal states of the ctr_drbg
	encrypt_engine(num_bytes_out, random_number_o);
	
	// Update the internal states of the ctr_drbg
	update(additional_input);

	// Increase the counter of generated random numbers since last reseed by 1
	reseed_counter++;
}


void ctr_drbg::encrypt_engine (unsigned int num_target_bytes, bytesNumber& output) {
	// Initialize the temporary buffer
	bytesNumber temp;
	unsigned int temp_len = 0;
	
	// Generate a sufficient number of bytes to update both the key and V values
	while (temp_len < num_target_bytes) {
		v = v + 1;	// increase the value of V by 1

		// Invoke the selected block function to generate the next random number.
		bytesNumber current_encryption;
		if (block_function_type == PRIMITIVE_CORE_AES) {
			current_encryption = block_function->generate_block(key, v);
		} else {
			bytesNumber keccak_input = v;
			keccak_input.appendHighSide(key);
			current_encryption = block_function->generate_block(keccak_input);
		}

		// Append the generated random bytes to the "temp" buffer, until enough are generated
		temp.appendLowSide(current_encryption);
		temp_len = temp.size();
	}

	// Get only the leftmost num_target_bytes bytes of the generated buffer
	temp = temp.getSlice(temp_len-1, temp_len-num_target_bytes);

	// Assign the generated random number
	output = temp;
}
