// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Top-level pipelined sequential implementation of AES-128 encryption.
// Input data and key are always registered at the first pipeline stage.
// valid_i marks when a new input block is valid; valid_o marks when output_o is valid.
// busy_o is asserted when at least one valid block is present inside the pipeline.
// ----------------------------------------------------------------------------------------------
// Reference:
// NIST FIPS 197-upd1 (May 9, 2023), Sec. 5.1 (CIPHER), Sec. 5.2 (KEYEXPANSION),
// Link to the FIPS 197 standard: https://doi.org/10.6028/NIST.FIPS.197-upd1
// ==============================================================================================

module AES_128_pipe (
	input	logic				clk_i,		// Clock
	input	logic				rst_n_i,		// Asynch. reset on Low
	input	logic				valid_i,
	input	logic [127 : 0] 	input_i,
	input	logic [127 : 0] 	key_i,
	output	logic [127 : 0] 	output_o,
	output	logic				valid_o,
	output	logic				busy_o
);
	// ==========================================================================================
	// ---------------------- Define consts and variables used in this module -------------------
	// ==========================================================================================

	// Constants of the module
	localparam int unsigned num_rounds		= 10;		// Number of iterations (rounds) done on the base Encrypting Algorithm (called "chiper")

	// Define signals used in the circuit	
	logic [127 : 0] state_after_addRoundKey	[num_rounds 	: 0];	// State after each AddRoundKey
	logic [127 : 0] state_after_subBytes	[num_rounds		: 1];	// State after each subBytes operation
	logic [127 : 0] state_after_shiftRows	[num_rounds		: 1];	// State after each shiftRows operation
	logic [127 : 0] state_after_mixColumns	[num_rounds		: 1];	// State after each mixColumns operation
	logic [127 : 0] key_nextRound			[(num_rounds-1)	: 0];

	// Pipeline registers
	logic [127 : 0] state_in_pipeStage		[(num_rounds+1)	: 0];	// State after the pipeline register. There are (num_rounds+1) pipeline registers in order to have inputs and outputs registered
	logic [127 : 0] key_in_pipeStage		[num_rounds		: 0];	
	logic [(num_rounds+1) : 0] valid_shiftReg;					// Shift register for the Valid Bit, used to keep track of when the DOUT is valid

	// ==========================================================================================
	// -------------------- Instantiate all sub-modules needed for this module ------------------
	// ==========================================================================================

	// Initial AddRoundKey (round 0)
	AES_addRoundKeys add_round_key_0_i (
		.state_i		(state_in_pipeStage[0]),
		.round_key_i	(key_in_pipeStage[0]),
		.state_o		(state_after_addRoundKey[0])
	);

	// Compute the key for round 1!
	AES_keyExpansion key_expansion_i (
		.round_key_i			(key_in_pipeStage[0]),
		.round_idx_i			(0),
		.next_round_key_o		(key_nextRound[0])
	);

	// Rounds (1 to (num_rounds-1)) (num_round executed in total)
	// Execute SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
	genvar round;
	generate
		for (round = 1; round < num_rounds; round++) begin : g_main_rounds
			AES_subTypes sub_bytes_i (
				.state_i	(state_in_pipeStage		[round]),
				.state_o	(state_after_subBytes	[round])
			);

			AES_shiftRows shift_rows_i (
				.state_i	(state_after_subBytes	[round]),
				.state_o	(state_after_shiftRows	[round])
			);

			AES_mixColumns mix_columns_i (
				.state_i	(state_after_shiftRows	[round]),
				.state_o	(state_after_mixColumns	[round])
			);

			AES_addRoundKeys add_round_key_i (
				.state_i		(state_after_mixColumns		[round]),
				.round_key_i	(key_in_pipeStage			[round]),
				.state_o		(state_after_addRoundKey	[round])
			);

			// Compute the key for the next round!
			AES_keyExpansion key_expansion_i (
				.round_key_i			(key_in_pipeStage[round]),
				.round_idx_i			(round),
				.next_round_key_o		(key_nextRound[round])
			);
		end
	endgenerate

	// Final round (round num_rounds)
	// SubBytes -> ShiftRows -> AddRoundKey
	AES_subTypes sub_bytes_final_i (
		.state_i	(state_in_pipeStage		[num_rounds]),
		.state_o	(state_after_subBytes	[num_rounds])
	);

	AES_shiftRows shift_rows_final_i (
		.state_i	(state_after_subBytes	[num_rounds]),
		.state_o	(state_after_shiftRows	[num_rounds])
	);

	AES_addRoundKeys add_round_key_final_i (
		.state_i		(state_after_shiftRows		[num_rounds]),
		.round_key_i	(key_in_pipeStage			[num_rounds]),
		.state_o		(state_after_addRoundKey	[num_rounds])
	);

	// ==========================================================================================
	// ---------------------------- Describe the pipeline connections ---------------------------
	// ==========================================================================================
 
	always_ff @(posedge clk_i or negedge rst_n_i) begin
		if (!rst_n_i) begin
			// Reset all register to a known state (reset to 0)
			for (int unsigned round_ff = 0; round_ff < (num_rounds+2); round_ff++) begin
				state_in_pipeStage	[round_ff] <= '0;
				valid_shiftReg	 	[round_ff] <= 1'b0;

				if (round_ff < (num_rounds+1)) begin
					key_in_pipeStage [round_ff] <= '0;
				end
			end
		end else begin
			// Assign the Input Values to the first pipeline stage
			state_in_pipeStage	[0] <= input_i;
			key_in_pipeStage	[0] <= key_i;
			valid_shiftReg		[0] <= valid_i;

			if (busy_o) begin
				// Assign the ouput values of previous round_ff, to the pipeline stage of next round_ff
				// No key is passed to the last register (because this is the ouput register and key is not needed
				// at the ouput) 
				for (int unsigned round_ff = 0; round_ff < (num_rounds+1); round_ff++) begin
					state_in_pipeStage	[round_ff+1] <= state_after_addRoundKey	[round_ff];
					valid_shiftReg		[round_ff+1] <= valid_shiftReg			[round_ff];
					
					if (round_ff < num_rounds) begin
						key_in_pipeStage [round_ff+1] <= key_nextRound[round_ff];
					end
				end
			end
		end
	end

	assign valid_o = valid_shiftReg[num_rounds+1];
	assign busy_o  =| valid_shiftReg;

	// Cipher output (output of AES 128)
	assign output_o = state_in_pipeStage [num_rounds+1];

endmodule
