// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Combinational implementation of the AES AddRoundKey transformation on a 128-bit state.
// The state is organized as a 4x4 byte matrix [row][column] in AES column-major order.
// Each output byte is obtained by XOR between state byte and round-key byte.
// ----------------------------------------------------------------------------------------------
// Reference:
// NIST FIPS 197-upd1 (May 9, 2023), Sec. 3.4 (State mapping), Sec. 5.1.4 (ADDROUNDKEY),
// Link to the FIPS 197 standard: https://doi.org/10.6028/NIST.FIPS.197-upd1
// ==============================================================================================

module AES_addRoundKeys (
	input  logic [127 : 0] state_i,
	input  logic [127 : 0] round_key_i,
	output logic [127 : 0] state_o
);

	logic [7 : 0] state_bytes      [3 : 0] [3 : 0];	// [row][colum] Organize the Input state into a 4x4 matrix of bytes
	logic [7 : 0] round_key_bytes  [3 : 0] [3 : 0];	// [row][colum] Organize the Round key into a 4x4 matrix of bytes
	logic [7 : 0] output_bytes     [3 : 0] [3 : 0];	// [row][colum] Organize the Output state into a 4x4 matrix of bytes

	// Connect the plain Input and Output vectors of 128 bits to the 4x4 byte matrix
	genvar row, col;
	generate
		for (row = 0; row < 4; row++) begin : map_rows
			for (col = 0; col < 4; col++) begin : map_cols
				// Compute the start of the current byte addess
				localparam int unsigned byteStartAddress = 8 * (row + (4*col));

				// Connect 8 bits from the Input state (starting from "byteStartAddress" position) to the 
				// current 4x4 matrix entry!
				assign state_bytes [row][col] = state_i[127 - byteStartAddress -: 8];

				// Connect 8 bits from the Round key (starting from "byteStartAddress" position) to the 
				// current 4x4 matrix entry!
				assign round_key_bytes [row][col] = round_key_i[127 - byteStartAddress -: 8];

				// Connect 8 bits from the Outpput state (starting from "byteStartAddress" position) to the 
				// current 4x4 matrix entry!
				assign state_o [127 - byteStartAddress -: 8] = output_bytes [row][col];
			end
		end
	endgenerate

	// Execute AddRoundKey by XORing byte by byte the state and the round key
	generate
		for (row = 0; row < 4; row++) begin : add_rows
			for (col = 0; col < 4; col++) begin : add_cols
				assign output_bytes[row][col] = state_bytes[row][col] ^ round_key_bytes[row][col];
			end
		end
	endgenerate

endmodule
