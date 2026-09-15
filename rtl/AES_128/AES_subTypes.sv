// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Combinational implementation of the AES SubBytes transformation on a 128-bit state.
// The state is organized as a 4x4 byte matrix [row][column] in AES column-major order.
// Each output byte is obtained by applying the AES S-box to the corresponding input byte. The 
// current state byte is used as pointer to the S-Box content, and the content in the S-Box is
// used as the output.
// ----------------------------------------------------------------------------------------------
// Reference:
// NIST FIPS 197-upd1 (May 9, 2023), Sec. 3.4 (State mapping), Sec. 5.1.1 (SUBBYTES),
// Table 4 (S-box), Link to the FIPS 197 standard: https://doi.org/10.6028/NIST.FIPS.197-upd1
// ==============================================================================================

module AES_subTypes (
	input  logic [127 : 0] state_i,
	output logic [127 : 0] state_o
);

	import AES_operations_pkg::*;

	logic [7 : 0] input_bytes  [3 : 0] [3 : 0];		// [row][colum] Organize the Input state into a 4x4 matrix of bytes
	logic [7 : 0] output_bytes [3 : 0] [3 : 0];		// [row][colum] Organize the Output state into a 4x4 matrix of bytes

	// Connect the plain Input and Output vectors of 128 bits to the 4x4 byte matrix
	genvar row_gen, col_gen;
	generate
		for (row_gen = 0; row_gen < 4; row_gen++) begin : map_row_gens
			for (col_gen = 0; col_gen < 4; col_gen++) begin : map_col_gens
				// Compute the start of the current byte addess
				localparam int unsigned byteStartAddress = 8 * (row_gen + (4*col_gen));
				
				// Connect 8 bits from the Input state (starting from "byteStartAddress" position) to the
				// current 4x4 matrix entry!
				assign input_bytes [row_gen][col_gen] = state_i[127 - byteStartAddress -: 8];
				
				// Connect 8 bits from the Outpput state (starting from "byteStartAddress" position) to the
				// current 4x4 matrix entry!
				assign state_o [127 - byteStartAddress -: 8] = output_bytes [row_gen][col_gen];
			end
		end
	endgenerate

	// Apply the AES S-box to each byte of the state matrix
	always_comb begin : subTypes
		for (int unsigned row = 0; row < 4; row++) begin
			for (int unsigned col = 0; col < 4; col++) begin
				// Get the current byte in the state matrix
				logic [7:0] currentByte = input_bytes[row][col];
				
					// Use the current byte of the state matrix as pointer for the sBox matrix
					// sBox is a 16x16 matrix, so 4 bits of currentByte are used to addess the row of
					// sBox and 4 bits are used to addess the column of sBox
					output_bytes[row][col] = AES_sBoxSubstitution(currentByte);
				end
			end
		end
		

endmodule
