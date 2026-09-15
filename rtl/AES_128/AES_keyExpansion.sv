// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Combinational implementation the single AES-128 step keyExpansion.
// Given the current round key (128-bit), this module generates only the next round key (128-bit).
// ----------------------------------------------------------------------------------------------
// Reference:
// NIST FIPS 197-upd1 (May 9, 2023), Sec. 5.2 (KEYEXPANSION), Alg. 2, Table 5 (Rcon),
// Table 4 (S-box), Link to the FIPS 197 standard: https://doi.org/10.6028/NIST.FIPS.197-upd1
// ==============================================================================================

module AES_keyExpansion (
	input  logic [127 : 0] round_key_i,
	input  logic [3   : 0] round_idx_i,		// Current round index (0..9)
	output logic [127 : 0] next_round_key_o
);

	import AES_operations_pkg::*;

	// Rotate word [a0,a1,a2,a3] -> [a1,a2,a3,a0]
	function automatic logic [31 : 0] RotWord(input logic [31 : 0] word_i);
		RotWord = {word_i[23 : 0], word_i[31 : 24]};
	endfunction

	// Apply S-box to all bytes 4 of a 32-bit word
	function automatic logic [31 : 0] SubWord(input logic [31 : 0] word_i);
		SubWord = {
			AES_sBoxSubstitution (word_i [31 : 24]),
			AES_sBoxSubstitution (word_i [23 : 16]),
			AES_sBoxSubstitution (word_i [15 : 8]),
			AES_sBoxSubstitution (word_i [7  : 0])
		};
	endfunction

	// Return Rcon word for the current step:
	// round_idx_i = 0 -> Rcon1, ..., round_idx_i = 9 -> Rcon10
	function automatic logic [31 : 0] RconWord(input logic [3 : 0] rcon_idx_i);
		case (rcon_idx_i)
			4'd0: RconWord = 32'h01000000;
			4'd1: RconWord = 32'h02000000;
			4'd2: RconWord = 32'h04000000;
			4'd3: RconWord = 32'h08000000;
			4'd4: RconWord = 32'h10000000;
			4'd5: RconWord = 32'h20000000;
			4'd6: RconWord = 32'h40000000;
			4'd7: RconWord = 32'h80000000;
			4'd8: RconWord = 32'h1b000000;
			4'd9: RconWord = 32'h36000000;
			default: RconWord = 32'h00000000;
		endcase
	endfunction

	// Execute one key expansion step:
	// {w0,w1,w2,w3} -> {w0',w1',w2',w3'}
	always_comb begin
		logic [31 : 0] w0, w1, w2, w3;
		logic [31 : 0] w0_next, w1_next, w2_next, w3_next;
		logic [31 : 0] g_word;

		w0 = round_key_i[127 : 96];
		w1 = round_key_i[95  : 64];
		w2 = round_key_i[63  : 32];
		w3 = round_key_i[31  : 0];

		g_word  = SubWord(RotWord(w3)) ^ RconWord(round_idx_i);
		w0_next = w0 ^ g_word;
		w1_next = w1 ^ w0_next;
		w2_next = w2 ^ w1_next;
		w3_next = w3 ^ w2_next;

		next_round_key_o = {w0_next, w1_next, w2_next, w3_next};
	end

endmodule
