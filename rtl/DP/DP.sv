// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module DP #(
	parameter int unsigned				LENGTH_STATE	= 32,	// Number of bits of the internal states of the DP
	parameter int unsigned				LENGTH_SEED		= 16,	// Number of bits of the Seed of the DP
	parameter logic [LENGTH_STATE-1:0] 	A 				= '0,	// Initial value of the "A" Internal state of DP	
	parameter logic [LENGTH_STATE-1:0] 	B 				= '0,	// Initial value of the "B" Internal state of DP
    parameter int unsigned 				start_odd 	= 1,
	parameter int unsigned				EXTRACTOR_CORE	= primitive_pkg::PRIMITIVE_CORE_KECCAK,
	parameter int unsigned				PRG_CORE		= primitive_pkg::PRIMITIVE_CORE_KECCAK
	) (
	input	logic 						clk_i,
	input	logic						nRST,	
	input	logic						request_Reseed,	
	input	logic						request_RandomNumber,
	input	logic	[LENGTH_SEED-1:0] 	seed,
	output	logic	 					ready_o,
	output	logic	 					valid_o,
	output	logic	 					busy_o,
	output	logic	[LENGTH_SEED-1:0] 	RandomNumber
);

	localparam int unsigned LENGTH = LENGTH_STATE;
	localparam int unsigned ZERO_FILL = 1600 - LENGTH_STATE - LENGTH_SEED;
	localparam int unsigned AES_BITS = 128;
	localparam int unsigned EXTRACTOR_OUT_BITS = LENGTH_STATE + LENGTH_SEED;

	logic RegAEn, RegBEn, RegSEEDEn, Mux_in_sel, mux_ext_sel, Ext_start, Ext_Done, Ext_Interr;
	logic PRNG_request_RandomNumber, PRNG_request_Reseed, PRNG_ready, PRNG_valid, PRNG_busy;
	logic rst_n_keccak;
	logic[LENGTH_STATE-1:0] Aout, Bout, PRNGout, mux_ext_out, Amux, Bmux;
	logic[LENGTH_SEED-1:0] Kout, Kmux, new_seed_from_keccak;
	logic[LENGTH_STATE-1:0] prg_input;
	logic[1599:0] extractor_keccak_in, extractor_keccak_out;

	MUX2 #(.LENGTH(LENGTH)) muxM0 (
		.IN_0	(A), 
		.IN_1	(PRNGout), 
		.SEL	(Mux_in_sel), 
		.OUT	(Amux)
	);

	MUX2 #(.LENGTH(LENGTH)) muxM1 (
		.IN_0	(B), 
		.IN_1	(PRNGout), 
		.SEL	(Mux_in_sel), 
		.OUT	(Bmux)
	);

	REG #(.LENGTH(LENGTH)) regA (
		.clk_i	(clk_i), 
		.nRST	(nRST), 
		.EN		(RegAEn), 
		.IN		(Amux), 
		.OUT	(Aout)
	);

	REG #(.LENGTH(LENGTH)) regB (
		.clk_i	(clk_i), 
		.nRST	(nRST), 
		.EN		(RegBEn), 
		.IN		(Bmux), 
		.OUT	(Bout)
	);

	REG #(.LENGTH(LENGTH_SEED)) regK (
		.clk_i	(clk_i), 
		.nRST	(nRST), 
		.EN		(RegSEEDEn), 
		.IN		(Kmux), 
		.OUT	(Kout)
	);

	MUX2 #(.LENGTH(LENGTH)) muxExt(
		.IN_0	(Aout), 
		.IN_1	(Bout), 
		.SEL	(mux_ext_sel), 
		.OUT	(mux_ext_out)
	);

	always_comb begin
		new_seed_from_keccak = extractor_keccak_out[LENGTH_STATE + LENGTH_SEED - 1 : LENGTH_STATE];
		prg_input = extractor_keccak_out[LENGTH_STATE-1:0];

		if (Mux_in_sel) begin
			Kmux = new_seed_from_keccak;
		end else begin
			Kmux = seed;
		end
	end

	assign extractor_keccak_in = {{ZERO_FILL{1'b0}}, Kout, mux_ext_out};
	assign RandomNumber = Kout;
	assign rst_n_keccak = nRST;

	generate
		if (EXTRACTOR_CORE == primitive_pkg::PRIMITIVE_CORE_KECCAK) begin : gen_extractor_keccak
			keccak_f ext (
				clk_i, 
				rst_n_keccak, 
				Ext_start, 
				extractor_keccak_in, 
				extractor_keccak_out, 
				Ext_Done, 
				Ext_Interr
			);

		end else if (EXTRACTOR_CORE == primitive_pkg::PRIMITIVE_CORE_AES) begin : gen_extractor_aes
			localparam int unsigned AES_KEY_COPY_BITS			= (LENGTH_SEED < AES_BITS) ? LENGTH_SEED : AES_BITS;
			localparam int unsigned AES_INPUT_COPY_BITS			= (LENGTH_STATE < AES_BITS) ? LENGTH_STATE : AES_BITS;
			localparam int unsigned AES_EXTRACTOR_COPY_BITS		= (EXTRACTOR_OUT_BITS < AES_BITS) ? EXTRACTOR_OUT_BITS : AES_BITS;

			logic [AES_BITS-1:0] aes_key;
			logic [AES_BITS-1:0] aes_input;
			logic [AES_BITS-1:0] aes_output;
			logic aes_busy;

			assign Ext_Interr = Ext_Done;

			initial begin
				if (LENGTH_SEED > AES_BITS) begin
					$fatal(1, "DP AES extractor requires LENGTH_SEED <= 128");
				end
				if (LENGTH_STATE > AES_BITS) begin
					$fatal(1, "DP AES extractor requires LENGTH_STATE <= 128");
				end
				if (EXTRACTOR_OUT_BITS > AES_BITS) begin
					$fatal(1, "DP AES extractor can generate at most 128 bits");
				end
			end

			always_comb begin
				aes_key = '0;
				aes_input = '0;
				extractor_keccak_out = '0;

				aes_key[AES_KEY_COPY_BITS-1:0] = Kout[AES_KEY_COPY_BITS-1:0];
				aes_input[AES_INPUT_COPY_BITS-1:0] = mux_ext_out[AES_INPUT_COPY_BITS-1:0];
				extractor_keccak_out[AES_EXTRACTOR_COPY_BITS-1:0] = aes_output[AES_EXTRACTOR_COPY_BITS-1:0];
			end

			AES_128 ext (
				.clk_i		(clk_i),
				.rst_n_i	(nRST),
				.valid_i	(Ext_start && !aes_busy),
				.input_i	(aes_input),
				.key_i		(aes_key),
				.output_o	(aes_output),
				.valid_o	(Ext_Done),
				.busy_o		(aes_busy)
			);

		end else begin : gen_extractor_unsupported
			initial begin
				$fatal(1, "Unsupported DP extractor core selection");
			end
		end

		if (PRG_CORE == primitive_pkg::PRIMITIVE_CORE_KECCAK) begin : gen_prg_keccak
			logic [1599:0] prg_keccak_in;
			logic [1599:0] prg_keccak_out;
			logic prg_keccak_status;

			assign prg_keccak_in = {{ZERO_FILL{1'b0}}, Kout, prg_input};
			assign PRNGout = prg_keccak_out[LENGTH_STATE-1:0];
			assign PRNG_ready = !PRNG_busy;

			keccak_f PRNG (
				clk_i,
				rst_n_keccak,
				PRNG_request_RandomNumber,
				prg_keccak_in,
				prg_keccak_out,
				prg_keccak_status,
				PRNG_valid
			);

			always_ff @(posedge clk_i) begin
				if (!nRST) begin
					PRNG_busy <= 1'b0;
				end else begin
					if (PRNG_request_RandomNumber && PRNG_ready) begin
						PRNG_busy <= 1'b1;
					end else if (PRNG_valid) begin
						PRNG_busy <= 1'b0;
					end
				end
			end

		end else if (PRG_CORE == primitive_pkg::PRIMITIVE_CORE_AES) begin : gen_prg_aes
			localparam int unsigned AES_KEY_COPY_BITS	= (LENGTH_SEED < AES_BITS) ? LENGTH_SEED : AES_BITS;
			localparam int unsigned AES_INPUT_COPY_BITS	= (LENGTH_STATE < AES_BITS) ? LENGTH_STATE : AES_BITS;
			localparam int unsigned AES_OUTPUT_COPY_BITS	= (LENGTH_STATE < AES_BITS) ? LENGTH_STATE : AES_BITS;

			logic [AES_BITS-1:0] aes_key;
			logic [AES_BITS-1:0] aes_input;
			logic [AES_BITS-1:0] aes_output;

			assign PRNG_ready = 1'b1;

			initial begin
				if (LENGTH_SEED > AES_BITS) begin
					$fatal(1, "DP AES PRG requires LENGTH_SEED <= 128");
				end
				if (LENGTH_STATE > AES_BITS) begin
					$fatal(1, "DP AES PRG can generate at most 128 bits");
				end
			end

			always_comb begin
				aes_key = '0;
				aes_input = '0;
				PRNGout = '0;

				aes_key[AES_KEY_COPY_BITS-1:0] = Kout[AES_KEY_COPY_BITS-1:0];
				aes_input[AES_INPUT_COPY_BITS-1:0] = prg_input[AES_INPUT_COPY_BITS-1:0];
				PRNGout[AES_OUTPUT_COPY_BITS-1:0] = aes_output[AES_OUTPUT_COPY_BITS-1:0];
			end

			AES_128 PRNG (
				.clk_i		(clk_i),
				.rst_n_i	(nRST),
				.valid_i	(PRNG_request_RandomNumber),
				.input_i	(aes_input),
				.key_i		(aes_key),
				.output_o	(aes_output),
				.valid_o	(PRNG_valid),
				.busy_o		(PRNG_busy)
			);

		end else begin : gen_prg_unsupported
			initial begin
				$fatal(1, "Unsupported DP PRG core selection");
			end
		end
	endgenerate

	DP_FSM #(
		.start_odd(start_odd)
	) fsm (
		.clk_i					(clk_i),
		.nRST					(nRST),
		.request_Reseed			(request_Reseed),
		.request_RandomNumber	(request_RandomNumber),
		.PRNG_ready				(PRNG_ready),
		.PRNG_valid				(PRNG_valid),
		.PRNG_busy				(PRNG_busy),
		.Ext_done				(Ext_Done),
		.RegAEn					(RegAEn),
		.RegBEn					(RegBEn),
		.RegSEEDEn				(RegSEEDEn),
		.Mux_in_sel				(Mux_in_sel),
		.mux_ext_sel			(mux_ext_sel),
		.Ext_start				(Ext_start),
		.PRNG_request_RandomNumber	(PRNG_request_RandomNumber),
		.PRNG_request_Reseed		(PRNG_request_Reseed),
		.ready_o				(ready_o),
		.valid_o				(valid_o),
		.busy_o					(busy_o)
	);

endmodule



	
