// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Helper functions for operations in GF(2^8) used by AES.
//
// Reference:
// - NIST FIPS 197-upd1 (May 9, 2023), Sec. 4.1 (Addition in GF(2^8))
// - NIST FIPS 197-upd1 (May 9, 2023), Sec. 4.2 (Multiplication in GF(2^8))
// Link to the FIPS 197 standard: https://doi.org/10.6028/NIST.FIPS.197-upd1
// ==============================================================================================

`timescale 1ns/1ps

package AES_operations_pkg;

	// AES S-box lookup table (Table 4 of FIPS 197)
	localparam logic [7 : 0] AES_sbox [0 : 15] [0 : 15] = '{
		'{8'h63, 8'h7c, 8'h77, 8'h7b, 8'hf2, 8'h6b, 8'h6f, 8'hc5, 8'h30, 8'h01, 8'h67, 8'h2b, 8'hfe, 8'hd7, 8'hab, 8'h76},
		'{8'hca, 8'h82, 8'hc9, 8'h7d, 8'hfa, 8'h59, 8'h47, 8'hf0, 8'had, 8'hd4, 8'ha2, 8'haf, 8'h9c, 8'ha4, 8'h72, 8'hc0},
		'{8'hb7, 8'hfd, 8'h93, 8'h26, 8'h36, 8'h3f, 8'hf7, 8'hcc, 8'h34, 8'ha5, 8'he5, 8'hf1, 8'h71, 8'hd8, 8'h31, 8'h15},
		'{8'h04, 8'hc7, 8'h23, 8'hc3, 8'h18, 8'h96, 8'h05, 8'h9a, 8'h07, 8'h12, 8'h80, 8'he2, 8'heb, 8'h27, 8'hb2, 8'h75},
		'{8'h09, 8'h83, 8'h2c, 8'h1a, 8'h1b, 8'h6e, 8'h5a, 8'ha0, 8'h52, 8'h3b, 8'hd6, 8'hb3, 8'h29, 8'he3, 8'h2f, 8'h84},
		'{8'h53, 8'hd1, 8'h00, 8'hed, 8'h20, 8'hfc, 8'hb1, 8'h5b, 8'h6a, 8'hcb, 8'hbe, 8'h39, 8'h4a, 8'h4c, 8'h58, 8'hcf},
		'{8'hd0, 8'hef, 8'haa, 8'hfb, 8'h43, 8'h4d, 8'h33, 8'h85, 8'h45, 8'hf9, 8'h02, 8'h7f, 8'h50, 8'h3c, 8'h9f, 8'ha8},
		'{8'h51, 8'ha3, 8'h40, 8'h8f, 8'h92, 8'h9d, 8'h38, 8'hf5, 8'hbc, 8'hb6, 8'hda, 8'h21, 8'h10, 8'hff, 8'hf3, 8'hd2},
		'{8'hcd, 8'h0c, 8'h13, 8'hec, 8'h5f, 8'h97, 8'h44, 8'h17, 8'hc4, 8'ha7, 8'h7e, 8'h3d, 8'h64, 8'h5d, 8'h19, 8'h73},
		'{8'h60, 8'h81, 8'h4f, 8'hdc, 8'h22, 8'h2a, 8'h90, 8'h88, 8'h46, 8'hee, 8'hb8, 8'h14, 8'hde, 8'h5e, 8'h0b, 8'hdb},
		'{8'he0, 8'h32, 8'h3a, 8'h0a, 8'h49, 8'h06, 8'h24, 8'h5c, 8'hc2, 8'hd3, 8'hac, 8'h62, 8'h91, 8'h95, 8'he4, 8'h79},
		'{8'he7, 8'hc8, 8'h37, 8'h6d, 8'h8d, 8'hd5, 8'h4e, 8'ha9, 8'h6c, 8'h56, 8'hf4, 8'hea, 8'h65, 8'h7a, 8'hae, 8'h08},
		'{8'hba, 8'h78, 8'h25, 8'h2e, 8'h1c, 8'ha6, 8'hb4, 8'hc6, 8'he8, 8'hdd, 8'h74, 8'h1f, 8'h4b, 8'hbd, 8'h8b, 8'h8a},
		'{8'h70, 8'h3e, 8'hb5, 8'h66, 8'h48, 8'h03, 8'hf6, 8'h0e, 8'h61, 8'h35, 8'h57, 8'hb9, 8'h86, 8'hc1, 8'h1d, 8'h9e},
		'{8'he1, 8'hf8, 8'h98, 8'h11, 8'h69, 8'hd9, 8'h8e, 8'h94, 8'h9b, 8'h1e, 8'h87, 8'he9, 8'hce, 8'h55, 8'h28, 8'hdf},
		'{8'h8c, 8'ha1, 8'h89, 8'h0d, 8'hbf, 8'he6, 8'h42, 8'h68, 8'h41, 8'h99, 8'h2d, 8'h0f, 8'hb0, 8'h54, 8'hbb, 8'h16}
	};

	// Apply AES S-box to a single byte
	// Use the given byte as pointer for the sBox matrix
	// sBox is a 16x16 matrix, so 4 bits of currentByte are used to addess the row of
	// sBox and 4 bits are used to addess the column of sBox
	function automatic logic [7 : 0] AES_sBoxSubstitution(
		input logic [7 : 0] in_byte
	);
		AES_sBoxSubstitution = AES_sbox[in_byte[7 : 4]][in_byte[3 : 0]];
	endfunction

	// Addition in GF(2^8): byte-wise XOR.
	function automatic logic [7:0] AES_add(
		input logic [7:0] a,
		input logic [7:0] b
	);
		AES_add = a ^ b;
	endfunction

	// Multiply by {02} in GF(2^8)
	function automatic logic [7:0] AES_mult2 (
		input logic [7:0] b
	);
		if (b[7] == 1'b1) begin
			AES_mult2 = {b[6:0], 1'b0} ^ 8'h1B;	// Result is: {b6,b5,b4,b3,b2,b1,b0,0} XOR {00011011}
		end
		else begin
			AES_mult2 = {b[6:0], 1'b0};			// Result is: {b6,b5,b4,b3,b2,b1,b0,0}
		end
	endfunction

	// Generic multiplication in GF(2^8): result = a * m
	function automatic logic [7:0] AES_mult(
		input logic [7:0] a,
		input logic [7:0] m
	);
		logic [7:0] product;
		logic [7:0] currentAdd;
		int unsigned i;

		product 	= 8'h00;	// Initialize the product to 0
		currentAdd	= a;	// Initialize the variable that holds the value of the mult2 associated to the current bit to the input operand "a"

		for (i = 0; i < 8; i++) begin
			// If the current bit of the multiplier is at 1, add the current value to the product
			if (m[i] == 1'b1) begin
				product = AES_add (product, currentAdd);
			end

			// Always compute the next value to add, even if not used in the next cycle
			currentAdd = AES_mult2(currentAdd);
		end

		// Assign the final result of multiplication to the output of the function
		AES_mult = product;
	endfunction

endpackage
