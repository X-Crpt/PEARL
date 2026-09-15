// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Combinational implementation of the AES MixColumns transformation on a 128-bit state.
// The state is organized as a 4x4 byte matrix [row][column] in AES column-major order.
// Each output column is computed from the corresponding input column by multiplying it
// by a fixed matrix whose coefficients are defined by the AES standard.
// ----------------------------------------------------------------------------------------------
// Reference:
// NIST FIPS 197-upd1 (May 9, 2023), Sec. 3.4 (State mapping), Sec. 5.1.3 (MIXCOLUMNS),
// Link to the FIPS 197 standard: https://doi.org/10.6028/NIST.FIPS.197-upd1
// ==============================================================================================

module AES_mixColumns (
	input  logic [127 : 0]	state_i,
	output logic [127 : 0]	state_o
);

	import AES_operations_pkg::*;

	// Define the 4x4 matrix used to transform each column into the output column
	// The value on this matrix are strictly defined by the AES 128 standard
	localparam logic [7 : 0] mix_columns_matrix [0 : 3] [0 : 3] = '{
		'{8'h02, 8'h03, 8'h01, 8'h01},	// 0x02, 0x03, 0x01, 0x01
		'{8'h01, 8'h02, 8'h03, 8'h01},	// 0x01, 0x02, 0x03, 0x01
		'{8'h01, 8'h01, 8'h02, 8'h03},	// 0x01, 0x01, 0x02, 0x03
		'{8'h03, 8'h01, 8'h01, 8'h02}	// 0x03, 0x01, 0x01, 0x02
	};



	logic [7 : 0] input_bytes  [3 : 0] [3 : 0];		// [row][colum] Organize the Input state into a 4x4 matrix of bytes
	logic [7 : 0] output_bytes [3 : 0] [3 : 0];		// [row][colum] Organize the Output state into a 4x4 matrix of bytes

	// Connect the plain Input and Output vectors of 128 bits to the 4x4 byte matrix
	genvar row, col;
	generate
		for (row = 0; row < 4; row++) begin : map_rows
			for (col = 0; col < 4; col++) begin : map_cols
				// Compute the start of the current byte addess
				localparam int unsigned byteStartAddress = 8 * (row + (4*col));					
				
				// Connect 8 bits from the Input state (starting from "byteStartAddress" position) to the 
				// current 4x4 matrix entry!
				assign input_bytes [row][col] = state_i[127 - byteStartAddress -: 8];		
				
				// Connect 8 bits from the Outpput state (starting from "byteStartAddress" position) to the 
				// current 4x4 matrix entry!
				assign state_o [127 - byteStartAddress -: 8] = output_bytes [row][col];
			end
		end
	endgenerate

	// Execute the mixColums, by executing the matrix multiplication (using Sum and Multiplication AES operation)
	// of input 4x4 state matrix, and a constant 4x4 matrix defined by AES 128 standard 
	always_comb begin
		for (int unsigned row_idx = 0; row_idx < 4; row_idx++) begin
			for (int unsigned col_idx = 0; col_idx < 4; col_idx++) begin
				
				output_bytes[row_idx][col_idx] = 8'h00;	// Initialize the byte I'm currently writing
				
				// Compute the byte as the sum of the 4 multiplications needed by the matrix multiplication
				for (int unsigned k_idx = 0; k_idx < 4; k_idx++) begin
					output_bytes[row_idx][col_idx] = AES_add(
						output_bytes[row_idx][col_idx],
						AES_mult (input_bytes[k_idx][col_idx], mix_columns_matrix[row_idx][k_idx])
					);
				end
			end
		end
	end
endmodule
