`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Common encryption engine for ctr_drbg operations, that can be used by multiple ctr_drbg 
// high level functions
// It executes the following pseudo-algorithm for a programmable number of times (selctable via 
// the "blocks_i" input), using a selectable block core:
//		1. V = V + 1 (mod 2^outlen)			--> Increment V, with overflow handling
//		2. block = Block_Core(Key, V)		--> Generate one output block using the selected core
//		3. temp = temp || block				--> Append the encryption on the high side of the output
//												vector
// Notes:
// - AES is the default core, so the original ctr_drbg behavior is unchanged.
// - Keccak can also be selected. In that case {key, V} is zero-padded to 1600 bits and the low
//   OUTLEN bits of the Keccak output are used as the generated block.
// - Number of blocks is runtime-selectable, the range from [0; MAX_BLOCKS].
// ================== ============================================================================

module ctr_drbg_encrypt_engine #(
	parameter int unsigned OUTLEN				= 128,
	parameter int unsigned KEYLEN				= 128,
	parameter int unsigned MAX_BLOCKS			= 8,
	parameter int unsigned FIFO_RECEIVE_DEPTH	= 2,
	parameter int unsigned ENCRYPTION_CORE		= primitive_pkg::PRIMITIVE_CORE_AES
) (
	input	logic								clk_i,			// Clock
	input	logic								rst_n_i,		// Synchronous Reset Signal (active low)
	input	logic								valid_i,		// Control Signal that indicates a new request for a new Random Number is active 
	input	logic 								concatenate_i,	// Control Signal that indicates this request needs to use the output V of the previous request
	input	logic [KEYLEN-1:0]					key_i,			// Key to be used during the AES core Random Number generation
	input	logic [OUTLEN-1:0]					v_i,			// Starting V for the AES core Random Number generation		
	input	logic [($clog2(MAX_BLOCKS+1))-1:0]	blocks_i,		// This value indicates the number of 
	output	logic								ready_o,		// Control Signal that indicates that the Unit is ready to receive a new random number generation request (via "valid_i")
	output	logic								busy_o,			// Control Signal that indicates some random number is being computed by the Unit
	output	logic								valid_o,		// Control Signal that indicates that value on "rand_number_o" is valid
	output	logic [MAX_BLOCKS*OUTLEN-1:0]		rand_number_o	// Ouput generated random number
);	

	// Santity check of parameters 
	// These checks are simulation-time checks and are useful to detect wrong module usage early.
	initial begin
		
	end

	localparam int unsigned FIFO_ISSUE_DEPTH		= 2;
	localparam int unsigned TEMP_BITS				= MAX_BLOCKS * OUTLEN;
	localparam int unsigned CNT_W					= $clog2(MAX_BLOCKS + 1);
	localparam int unsigned FIFO_ISSUE_DATA_BITS	= KEYLEN + OUTLEN + CNT_W + 1;
	localparam int unsigned FIFO_RECEIVE_DATA_BITS	= CNT_W;


	// Signals needed to handle the current request
	logic [CNT_W-1:0]		blocks_issued;				// Number of blocks issued of the request being issued right now 
	logic [CNT_W-1:0]		blocks_received;

	// Common interface used to connect the selected block core.
	logic					block_valid_i;
	logic					block_ready_o;
	logic [OUTLEN-1:0]		block_input_i;
	logic [KEYLEN-1:0]		block_key_i;
	logic [OUTLEN-1:0]		block_output_o;
	logic					block_valid_o;
	/* verilator lint_off UNUSEDSIGNAL */
	logic					block_busy_o;
	/* verilator lint_on UNUSEDSIGNAL */

	// Signals used to connect to the issue FIFO
	logic								fifo_issue_push_i;
	logic								fifo_issue_pop_i;
	logic [FIFO_ISSUE_DATA_BITS-1:0]	fifo_issue_data_i;
	logic [FIFO_ISSUE_DATA_BITS-1:0]	fifo_issue_data_o;
	logic								fifo_issue_empty_o;
	logic								fifo_issue_full_o;

	// Signals used to connect to the receive FIFO
	logic								fifo_receive_push_i;
	logic								fifo_receive_pop_i;
	logic [FIFO_RECEIVE_DATA_BITS-1:0]	fifo_receive_data_i;
	logic [FIFO_RECEIVE_DATA_BITS-1:0]	fifo_receive_data_o;
	logic								fifo_receive_empty_o;
	logic								fifo_receive_full_o;

	logic [KEYLEN-1:0]	fifo_key;
	logic [OUTLEN-1:0]	fifo_v;
	logic [CNT_W-1:0]	fifo_issue_blocks;
	logic 				fifo_concatenate;
	logic [OUTLEN-1:0]	current_v;
	logic 				do_issue_pop;
	logic				issue_fire;
	
	logic [CNT_W-1:0]	fifo_receive_blocks;
	logic 				do_receive_pop;
	logic				receive_fire;

	
	// Instantiate the sub-components
	FIFO #(
		.DATA_WIDTH	(FIFO_ISSUE_DATA_BITS),
		.DEPTH		(FIFO_ISSUE_DEPTH)
	) u_fifo_issue (
		.clk_i		(clk_i),
		.rst_n_i	(rst_n_i),
		.push_i		(fifo_issue_push_i),
		.pop_i		(fifo_issue_pop_i),
		.data_i		(fifo_issue_data_i),
		.data_o		(fifo_issue_data_o),
		.empty_o	(fifo_issue_empty_o),
		.full_o		(fifo_issue_full_o)
	);

	FIFO #(
		.DATA_WIDTH	(FIFO_RECEIVE_DATA_BITS),
		.DEPTH		(FIFO_RECEIVE_DEPTH)
	) u_fifo_receive (
		.clk_i		(clk_i),
		.rst_n_i	(rst_n_i),
		.push_i		(fifo_receive_push_i),
		.pop_i		(fifo_receive_pop_i),
		.data_i		(fifo_receive_data_i),
		.data_o		(fifo_receive_data_o),
		.empty_o	(fifo_receive_empty_o),
		.full_o		(fifo_receive_full_o)
	);

	generate
		if (ENCRYPTION_CORE == primitive_pkg::PRIMITIVE_CORE_AES) begin : gen_aes_core
			// AES is fully pipelined in this project, so it can accept a new block every cycle.
			assign block_ready_o = 1'b1;

			AES_128 u_aes_128_block_stream (
				.clk_i		(clk_i),
				.rst_n_i	(rst_n_i),
				.valid_i	(block_valid_i),
				.input_i	(block_input_i),
				.key_i		(block_key_i),
				.output_o	(block_output_o),
				.valid_o	(block_valid_o),
				.busy_o		(block_busy_o)
			);

		end else if (ENCRYPTION_CORE == primitive_pkg::PRIMITIVE_CORE_KECCAK) begin : gen_keccak_core
			localparam int unsigned KECCAK_STATE_BITS	= 1600;
			localparam int unsigned KECCAK_INPUT_BITS	= KEYLEN + OUTLEN;
			localparam int unsigned KECCAK_ZERO_PAD_BITS	= KECCAK_STATE_BITS - KECCAK_INPUT_BITS;

			logic [KECCAK_STATE_BITS-1:0] keccak_input;
			logic [KECCAK_STATE_BITS-1:0] keccak_input_q;
			logic [KECCAK_STATE_BITS-1:0] keccak_output;
			logic keccak_status;
			logic keccak_done;
			logic keccak_busy;

			assign keccak_input		= {{KECCAK_ZERO_PAD_BITS{1'b0}}, block_key_i, block_input_i};
			assign block_output_o	= keccak_output[OUTLEN-1:0];
			assign block_valid_o	= keccak_done;
			assign block_busy_o		= keccak_busy;
			assign block_ready_o	= !keccak_busy;

			always_ff @(posedge clk_i) begin
				if (!rst_n_i) begin
					keccak_busy		<= 1'b0;
					keccak_input_q	<= '0;
				end else begin
					if (block_valid_i && block_ready_o) begin
						keccak_busy		<= 1'b1;
						keccak_input_q	<= keccak_input;
					end else if (keccak_done) begin
						keccak_busy		<= 1'b0;
					end
				end
			end

			keccak_f u_keccak_block_stream (
				.clk			(clk_i),
				.rst_n			(rst_n_i),
				.start_i		(block_valid_i && block_ready_o),
				.Din			(keccak_input_q),
				.Dout			(keccak_output),
				.status_d		(keccak_status),
				.keccak_intr	(keccak_done)
			);

		end else begin : gen_unsupported_core
			initial begin
				$fatal(1, "Unsupported ctr_drbg encryption core selection");
			end

			assign block_ready_o	= 1'b0;
			assign block_output_o	= '0;
			assign block_valid_o	= 1'b0;
			assign block_busy_o		= 1'b0;
		end
	endgenerate
	
	// ISSUE / PUSH control logic.
	always_comb begin
		fifo_issue_push_i	= 1'b0;
		fifo_issue_pop_i	= 1'b0;
		fifo_issue_data_i	= '0;

		fifo_receive_push_i	= 1'b0;
		fifo_receive_pop_i	= 1'b0;
		fifo_receive_data_i	= '0;

		block_valid_i	= 1'b0;
		block_input_i	= '0;
		block_key_i		= '0;

		// Accept a new request only when both internal FIFOs can accept it.
		if (valid_i && ready_o && (blocks_i != '0)) begin
			fifo_issue_push_i	= 1'b1;
			fifo_issue_data_i	= {key_i, v_i, blocks_i, concatenate_i};

			fifo_receive_push_i	= 1'b1;
			fifo_receive_data_i	= blocks_i;
		end

		// Issue one block from the head request when the selected core can accept it.
		if (issue_fire) begin
			block_valid_i	= 1'b1;
			block_key_i		= fifo_key;

			if (blocks_issued == CNT_W'(0)) begin
				// concatenate_i means: continue from previous request final V.
				if (fifo_concatenate) begin
					block_input_i = current_v + OUTLEN'(1);
				end else begin
					block_input_i = fifo_v + OUTLEN'(1);
				end
			end else begin
				block_input_i = current_v + OUTLEN'(1);
			end

			if (do_issue_pop) begin
				fifo_issue_pop_i = 1'b1;
			end
		end

		if (do_receive_pop) begin
			fifo_receive_pop_i = 1'b1;
		end
	end

	always_ff @(posedge clk_i) begin
		if (!rst_n_i) begin
			blocks_issued	<= '0;
			current_v		<= '0;
		end else begin
			if (issue_fire) begin
				if (blocks_issued == CNT_W'(0)) begin
					if (fifo_concatenate) begin
						current_v <= current_v + OUTLEN'(1);
					end else begin
						current_v <= fifo_v + OUTLEN'(1);
					end
				end else begin
					current_v <= current_v + OUTLEN'(1);
				end

				if (do_issue_pop) begin
					blocks_issued <= '0;
				end else begin
					blocks_issued <= blocks_issued + CNT_W'(1);
				end
			end
		end
	end

	// Issue path can accept a new request whenever the internal FIFOs have free space,
	// or a pop happens in the same cycle.
	assign issue_fire			= !fifo_issue_empty_o && block_ready_o;
	assign receive_fire			= !fifo_receive_empty_o && block_valid_o;
	assign do_issue_pop			= issue_fire && ((blocks_issued + CNT_W'(1)) >= fifo_issue_blocks);
	assign do_receive_pop		= receive_fire && ((blocks_received + CNT_W'(1)) >= fifo_receive_blocks); 
	
	assign fifo_concatenate		= fifo_issue_data_o [0];
	assign fifo_issue_blocks	= fifo_issue_data_o [CNT_W : 1];
	assign fifo_v				= fifo_issue_data_o [CNT_W + OUTLEN : CNT_W + 1];
	assign fifo_key				= fifo_issue_data_o [FIFO_ISSUE_DATA_BITS - 1 : CNT_W + OUTLEN + 1];
	assign fifo_receive_blocks	= fifo_receive_data_o; 

	assign ready_o				= (!fifo_issue_full_o || do_issue_pop) & (!fifo_receive_full_o || do_receive_pop);			// The FIFO is ready to accept if it is not full, or if it is full but I'll pop in the same cycle
	assign busy_o				= (!fifo_issue_empty_o) || (!fifo_receive_empty_o); 

	// RECEIVE HANDLING 
	always_ff @(posedge clk_i) begin
		if (!rst_n_i) begin
			valid_o				<= 1'b0;
			rand_number_o		<= '0;
			blocks_received		<= '0;
			
		end else begin 
			valid_o				<= 1'b0;
			
			// Check if there is some request in the FIFO to be handled
			if (receive_fire) begin
				rand_number_o	<= (rand_number_o << OUTLEN) | TEMP_BITS'(block_output_o);

				if (do_receive_pop) begin
					blocks_received		<= '0;
					valid_o				<= 1'b1;
				end else begin
					blocks_received <= blocks_received + CNT_W'(1);
				end
			end
		end
	end
endmodule
