`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// This module implements the top-level control logic for an AES-128 based ctr_drbg,
// following the main data flow described by NIST SP 800-90A for the ctr_drbg mechanism.
// The internal state of the generator is composed of:
// - Key: the AES key used by the block encryption engine.
// - V: the counter value encrypted by AES after being incremented inside the engine.
// - reseed_counter: the number of generate operations performed since the last
//   instantiate/reseed operation.
//
// The datapath is intentionally built around a single shared encryption engine
// (ctr_drbg_encrypt_engine). This keeps the area cost low, but it also means that the
// top-level control logic must carefully schedule all requests sent to the engine.
// The same engine is reused for:
// - Instantiation: performs ctr_drbg_Update with Key = 0, V = 0 and entropy_i as
//   provided_data.
// - Generation: encrypts the required number of counter blocks and returns the requested
//   random bits.
// - Post-generation update: performs ctr_drbg_Update after every generate operation,
//   using zero provided_data, to update Key and V for backtracking resistance.
// - Reseed: performs ctr_drbg_Update using fresh entropy_i as provided_data.
//
// Synchronization approach
// ----------------------------------------------------------------------------------------------
// The control FSM and the engine output path are synchronized through a small FIFO
// (u_fifo_issue). Every time the FSM successfully issues a request to the encryption engine, it
// pushes the type of that request into the FIFO:
// - OP_GENERATE: the next valid engine output must be interpreted as random output bits.
// - OP_UPDATE:   the next valid engine output must be interpreted as a new Key/V state.
//
// The FIFO is needed because the engine is pipelined/latency-based: the request is accepted in
// one cycle, while the corresponding result is produced later. When engine_valid_o is asserted,
// the FIFO head tells this module how to decode engine_rand_number_o. This keeps request issue
// and response receive aligned even if the engine latency changes.
//
// Update barrier
// ----------------------------------------------------------------------------------------------
// UPDATE operations modify the critical internal state (Key and V). Therefore, a GENERATE request
// must never be issued while a previous UPDATE is still waiting for its result. The update_pending
// flag implements this barrier:
// - It is set when an OP_UPDATE request is issued.
// - It is cleared only when the corresponding OP_UPDATE result is received and Key/V have been
//   updated.
// - S_GENERATE_WAIT and S_RESEED_WAIT hold the FSM until update_pending is cleared.
//
// Request buffering
// ----------------------------------------------------------------------------------------------
// External random-number requests are stored in a small FIFO together with their entropy input.
// This allows the unit to accept a small number of requests while it is busy, while preserving the
// request-based semantics expected by the golden model.
// ==============================================================================================

module ctr_drbg #(
	parameter int unsigned OUTLEN			= 128,	// Length of block-cipher output
	parameter int unsigned KEYLEN			= 128,	// Length of block-cipher key
	parameter int unsigned REQ_NUM_BITS		= 128,	// Number of bits requested by each generate call
	parameter int unsigned RESEED_CTR_BITS	= 8,	// Number of bits used for the counter before reseed
	parameter int unsigned ENCRYPTION_CORE	= primitive_pkg::PRIMITIVE_CORE_AES
) (
	input	logic						clk_i,
	input	logic						rst_n_i,
	input	logic						request_RN_i,
	input	logic [KEYLEN+OUTLEN-1:0]	entropy_i,
	output	logic						ready_o,
	output	logic						busy_o,
	output	logic						valid_o,
	output	logic [REQ_NUM_BITS-1:0]	output_RN_o
);

	localparam int unsigned SEEDLEN = KEYLEN + OUTLEN;

	localparam int unsigned BLOCKS_GENERATE 		= (REQ_NUM_BITS + OUTLEN - 1) / OUTLEN; // ceil(REQ_NUM_BITS / OUTLEN)
	localparam int unsigned BLOCKS_UPDATE   		= (SEEDLEN + OUTLEN - 1) / OUTLEN;      // ceil(SEEDLEN / OUTLEN)
	localparam int unsigned ENGINE_MAX_BLOCKS		= (BLOCKS_GENERATE > BLOCKS_UPDATE) ? BLOCKS_GENERATE : BLOCKS_UPDATE;
	localparam int unsigned BLOCKS_WIDTH			= $clog2(ENGINE_MAX_BLOCKS + 1);

	localparam int unsigned ENGINE_OUT_BITS 		= ENGINE_MAX_BLOCKS * OUTLEN;
	localparam int unsigned GENERATE_BITS   		= BLOCKS_GENERATE * OUTLEN;
	localparam int unsigned UPDATE_BITS     		= BLOCKS_UPDATE * OUTLEN;

	localparam int unsigned RESEED_CTR_MAX			= (2**RESEED_CTR_BITS) - 1;

	localparam int unsigned REQUEST_PENDING_BITS	= 2;
	localparam int unsigned REQUEST_PENDING_MAX		= (2**REQUEST_PENDING_BITS) - 1;

	// Set while an OP_UPDATE request has been issued but its result has not yet updated Key/V.
	logic update_pending;

	// The FSM may issue a new engine request only when both the engine and the operation FIFO
	// can accept it in the current cycle.
	logic can_issue_engine;

	// Main scheduler states.
	// WAIT states are used to stop the FSM while an UPDATE is still pending, because UPDATE changes
	// the internal state consumed by the following GENERATE or RESEED operation.
	typedef enum logic [2:0] {
		S_INSTANTIATE,
		S_RESEED_WAIT,
		S_RESEED,
		S_GENERATE_WAIT,
		S_GENERATE,
		S_UPDATE_CONCAT
	} main_state_t;
	main_state_t state;

	// Type associated with each request sent to the engine. This value is stored in u_fifo_issue
	// and later used to decode the corresponding engine output.
	localparam int unsigned OP_TYPE_BITS = 1;
	typedef enum logic [(OP_TYPE_BITS-1) : 0] {
		OP_UPDATE,
		OP_GENERATE	
	} operation_type_t;
	

	logic [KEYLEN-1:0] 			key;
	logic [OUTLEN-1:0] 			v;
	logic [RESEED_CTR_BITS-1:0] reseed_counter;

	// FIFO containing the entropy associated with each accepted external generate request.
	logic						req_fifo_push_i;
	logic						req_fifo_pop_i;
	logic [SEEDLEN-1:0]			req_fifo_data_o;
	logic						req_fifo_empty_o;
	logic						req_fifo_full_o;
	
	// provided_data used by ctr_drbg_Update. During instantiate/reseed this is entropy_i;
	// during the post-generation update this is forced to zero. Its length is SEEDLEN;
	// UPDATE_BITS may be larger only because the engine generates complete OUTLEN blocks.
	logic [SEEDLEN-1:0] 	provided_data_reg;

	// Shared block-stream engine interface.
	logic 						engine_valid_i;
	logic 						engine_concatenate_i;
	logic [KEYLEN-1:0] 			engine_key_i;
	logic [OUTLEN-1:0] 			engine_v_i;
	logic [BLOCKS_WIDTH-1:0] 	engine_blocks_i;
	logic 						engine_ready_o;
	logic 						engine_busy_o;
	logic 						engine_valid_o;
	logic [ENGINE_OUT_BITS-1:0] engine_rand_number_o;

	ctr_drbg_encrypt_engine #(
		.OUTLEN				(OUTLEN),
		.KEYLEN				(KEYLEN),
		.MAX_BLOCKS			(ENGINE_MAX_BLOCKS),
		.ENCRYPTION_CORE	(ENCRYPTION_CORE)
	) u_ctr_drbg_encrypt_engine (
		.clk_i			(clk_i),
		.rst_n_i		(rst_n_i),
		.valid_i		(engine_valid_i),
		.concatenate_i	(engine_concatenate_i),
		.key_i			(engine_key_i),
		.v_i			(engine_v_i),
		.blocks_i		(engine_blocks_i),
		.ready_o		(engine_ready_o),
		.busy_o			(engine_busy_o),
		.valid_o		(engine_valid_o),
		.rand_number_o	(engine_rand_number_o)
	);


	// Operation tracking FIFO.
	// The FIFO stores one OP_* tag for every request accepted by the engine. When the engine
	// later asserts engine_valid_o, fifo_data_o identifies how that output must be consumed.
	logic						fifo_push_i;
	logic						fifo_pop_i;
	logic [OP_TYPE_BITS-1:0]	fifo_data_i;
	logic [OP_TYPE_BITS-1:0]	fifo_data_o;
	logic						fifo_empty_o;
	logic						fifo_full_o;

	FIFO #(
		.DATA_WIDTH	(OP_TYPE_BITS),
		.DEPTH		(2)
	) u_fifo_issue (
		.clk_i		(clk_i),
		.rst_n_i	(rst_n_i),
		.push_i		(fifo_push_i),
		.pop_i		(fifo_pop_i),
		.data_i		(fifo_data_i),
		.data_o		(fifo_data_o),
		.empty_o	(fifo_empty_o),
		.full_o		(fifo_full_o)
	);

	FIFO #(
		.DATA_WIDTH	(SEEDLEN),
		.DEPTH		(REQUEST_PENDING_MAX)
	) u_fifo_requests (
		.clk_i		(clk_i),
		.rst_n_i	(rst_n_i),
		.push_i		(req_fifo_push_i),
		.pop_i		(req_fifo_pop_i),
		.data_i		(entropy_i),
		.data_o		(req_fifo_data_o),
		.empty_o	(req_fifo_empty_o),
		.full_o		(req_fifo_full_o)
	);

	always_comb begin
		// Default values: no engine request is issued unless the active FSM state enables it.
		engine_valid_i			= 1'b0;
		engine_key_i			= '0;
		engine_v_i				= '0;
		engine_blocks_i			= '0;
		engine_concatenate_i	= 1'b0;

		case (state)
			S_INSTANTIATE: begin
				// First update of the DRBG state: Key and V start from zero.
				engine_valid_i	= can_issue_engine;
				engine_key_i	= '0;
				engine_v_i		= '0;
				engine_blocks_i	= BLOCKS_WIDTH'(BLOCKS_UPDATE);
			end

			S_RESEED: begin
				// Reseed updates the current Key/V using fresh entropy as provided_data.
				engine_valid_i	= can_issue_engine;
				engine_key_i	= key;
				engine_v_i		= v;
				engine_blocks_i	= BLOCKS_WIDTH'(BLOCKS_UPDATE);
			end

			S_GENERATE: begin
				// Generate random bits only when at least one external request is pending.
				engine_valid_i	= can_issue_engine && !req_fifo_empty_o;
				engine_key_i	= key;
				engine_v_i		= v;
				engine_blocks_i	= BLOCKS_WIDTH'(BLOCKS_GENERATE);
			end

			S_UPDATE_CONCAT: begin
				// Post-generation update. concatenate_i tells the engine to continue from the
				// V value reached by the previous generate operation.
				engine_valid_i			= can_issue_engine;
				engine_key_i			= key;
				engine_v_i				= v;
				engine_blocks_i			= BLOCKS_WIDTH'(BLOCKS_UPDATE);
				engine_concatenate_i	= 1'b1;
			end

			default: ;

		endcase
	end

	logic accept_req;
	logic issue_req;

	// accept_req tracks the external interface; issue_req tracks a pending request that is
	// actually sent to the engine in this cycle.
	assign accept_req = request_RN_i && ready_o;
	assign issue_req  = (state == S_GENERATE) && can_issue_engine && !req_fifo_empty_o;
	assign req_fifo_push_i = accept_req;
	assign req_fifo_pop_i  = issue_req;

	always_ff @(posedge clk_i) begin
		logic [(SEEDLEN-1) : 0] temp;
		logic [(UPDATE_BITS-1) : 0] update_temp;
		logic [(GENERATE_BITS-1) : 0] generate_temp;
		
		if (!rst_n_i) begin
			state 					<= S_INSTANTIATE;
			provided_data_reg		<= '0;
			fifo_push_i 			<= 1'b0;
			fifo_data_i 			<= OP_UPDATE;
			key						<= '0;
			v						<= '0;
			valid_o					<= 1'b0;
			update_pending 			<= 1'b0;
			fifo_pop_i 				<= 1'b0;

		end else begin
			// Default registered controls. They are asserted for one cycle only when the FSM
			// issues a request or consumes an engine response.
			fifo_push_i <= 1'b0;
			fifo_data_i <= OP_UPDATE;
			valid_o		<= 1'b0;
			fifo_pop_i <= 1'b0;

			case (state)
				S_INSTANTIATE: begin
					if (can_issue_engine) begin
						// Launch initial ctr_drbg_Update with zero Key/V and entropy_i.
						state				<= S_GENERATE_WAIT;
						provided_data_reg	<= entropy_i;
						reseed_counter 		<= '0;

						update_pending <= 1'b1;

						fifo_push_i <= 1'b1;
						fifo_data_i <= OP_UPDATE;
					end
				end

				S_RESEED_WAIT: begin
					// Wait until the previous update has really committed the new Key/V.
					if (!update_pending) begin
						state <= S_RESEED;
					end
				end

				S_RESEED: begin
					if (can_issue_engine && !req_fifo_empty_o) begin
						// Launch reseed update. New random output is blocked until it completes.
						state 				<= S_GENERATE_WAIT;
						provided_data_reg	<= req_fifo_data_o;
						reseed_counter		<= '0;

						update_pending 		<= 1'b1;

						fifo_push_i 		<= 1'b1;
						fifo_data_i 		<= OP_UPDATE;
					end
				end

				S_GENERATE_WAIT: begin
					// Normal idle state after instantiate/reseed/update: generation can resume
					// only after Key/V are no longer pending.
					if (!update_pending) begin
						state <= S_GENERATE;
					end
				end

				S_GENERATE: begin
					if (issue_req) begin
						// Launch one generate operation and immediately schedule the mandatory
						// post-generation update as the next FSM phase.
						state 				<= S_UPDATE_CONCAT;
						provided_data_reg	<= req_fifo_data_o;
						reseed_counter 		<= reseed_counter + 1;

						fifo_push_i <= 1'b1;
						fifo_data_i <= OP_GENERATE;
					end
				end

				S_UPDATE_CONCAT: begin
					if (can_issue_engine) begin
						// Launch the post-generation update. The next state depends on the
						// reseed counter, but both paths first wait for this update to complete.
						if (reseed_counter >= RESEED_CTR_BITS'(RESEED_CTR_MAX)) begin
							state <= S_RESEED_WAIT;
						end else begin
							state <= S_GENERATE_WAIT;
						end
						provided_data_reg	<= '0;

						update_pending <= 1'b1;
						fifo_push_i <= 1'b1;
						fifo_data_i <= OP_UPDATE;
					end				
				end
				
				default: ;
			endcase

			// Engine response handling. The FIFO head identifies the operation that produced
			// this response, so output decoding remains aligned with request issue order.
			if (!fifo_empty_o & engine_valid_o) begin
				case (fifo_data_o)
					OP_UPDATE: begin
						// The engine packs the newest request in the low part of rand_number_o.
						// For update, first select the meaningful UPDATE_BITS, then take the leftmost SEEDLEN.
						update_temp	= engine_rand_number_o[(UPDATE_BITS-1):0];
						temp 		= update_temp[(UPDATE_BITS-1) -: SEEDLEN];
						temp		= temp ^ provided_data_reg; 
						key			<= temp [(SEEDLEN-1) 	-: KEYLEN];					// Leftmost keylen bits of "temp" 
						v			<= temp [(OUTLEN-1)		: 0 ];						// Rightmost outlen bits of "temp"

						update_pending <= 1'b0;
					end

					OP_GENERATE: begin
						// For generate, first select the meaningful GENERATE_BITS, then keep the leftmost requested bits.
						generate_temp = engine_rand_number_o[(GENERATE_BITS-1):0];
						output_RN_o	<= generate_temp[(GENERATE_BITS-1) -: REQ_NUM_BITS];
						valid_o		<= 1'b1;
					end
				endcase
				fifo_pop_i <= 1'b1;
			end
		end
	end

	// A new engine request is legal only if:
	// - the operation FIFO can store the OP_* tag for the request, or it is being popped now;
	// - the encryption engine is ready to accept a new request.
	assign can_issue_engine		= (!fifo_full_o | fifo_pop_i) & engine_ready_o;

	// ready_o refers only to the external request queue. The unit can be busy internally while
	// still accepting a limited number of new requests.
	assign ready_o 	= !req_fifo_full_o;
	assign busy_o	= engine_busy_o || !fifo_empty_o || !req_fifo_empty_o;

endmodule
