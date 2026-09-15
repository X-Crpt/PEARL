`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

`default_nettype none

module TB_ctr_drbg #(
	parameter int unsigned OUTLEN			= 128,	// Length of block-cipher output
	parameter int unsigned KEYLEN			= 128,	// Length of block-cipher key
	parameter int unsigned REQ_NUM_BITS		= 128,	// Number of bits requested by each generate call
	parameter int unsigned RESEED_CTR_BITS	= 8,	// Number of bits used for the counter before reseed
	parameter int unsigned ENCRYPTION_CORE	= primitive_pkg::PRIMITIVE_CORE_AES
);;

	// ===============================================================
	// Testbench Signals and constants
	// ===============================================================
	localparam time T_clk = 10ns;
	localparam int unsigned SEEDLEN = KEYLEN + OUTLEN;

	logic				clk_i_TB;
	logic				rst_n_i_TB;
	logic				request_RN_i_TB;
	logic [SEEDLEN-1:0]	entropy_i_TB;
	logic				inputs_end_TB;
	logic				ready_o_TB;
	logic [REQ_NUM_BITS-1:0]	output_o_TB;
	logic				valid_o_TB;
	logic				busy_o_TB;
	string				vcdFile;

	// ===============================================================
	// Generate Clock signal
	// ===============================================================
	initial begin
		vcdFile = "";

		// Get the VCD dump file path from command line
		// Example: +VCD_FILE=./SIM/AES_128/logs/AES_128.vcd
		$value$plusargs("VCD_FILE=%s", vcdFile);

		if (vcdFile == "") begin
			$fatal(1, "Missing +VCD_FILE plusarg for VCD dump path");
		end

		clk_i_TB = 1'b0;
		$dumpfile(vcdFile);
		$dumpvars(0, TB_ctr_drbg);
	end

	always #(T_clk/2) clk_i_TB <= ~clk_i_TB;

	// ===============================================================
	// Instance of the Unit Under Test
	// ===============================================================
	ctr_drbg #(
		.OUTLEN				(OUTLEN),
		.KEYLEN				(KEYLEN),
		.REQ_NUM_BITS		(REQ_NUM_BITS),
		.RESEED_CTR_BITS	(RESEED_CTR_BITS),
		.ENCRYPTION_CORE	(ENCRYPTION_CORE)
	) UUT (
		.clk_i			(clk_i_TB),
		.rst_n_i			(rst_n_i_TB),
		.request_RN_i	(request_RN_i_TB),
		.entropy_i		(entropy_i_TB),
		.ready_o	(ready_o_TB),
		.output_RN_o	(output_o_TB),
		.valid_o		(valid_o_TB),
		.busy_o			(busy_o_TB)
	);

	// ===============================================================
	// Modules used to generate and Check the Test signals for UUT!
	// ===============================================================

	// Generate Input Signals for the UUT
	data_maker #(
		.SEEDLEN	(SEEDLEN)
	) mkr (
		.clk_i			(clk_i_TB),
		.ready_o	(ready_o_TB),
		.rst_n_i			(rst_n_i_TB),
		.request_RN_i	(request_RN_i_TB),
		.entropy_i		(entropy_i_TB),
		.inputs_end		(inputs_end_TB)
	);

	// Check Outputs of the UUT for correctness!
	data_sink #(
		.REQ_NUM_BITS	(REQ_NUM_BITS)
	) snk (
		.clk_i			(clk_i_TB),
		.inputs_end		(inputs_end_TB),
		.request_RN_i	(request_RN_i_TB),
		.ready_o	(ready_o_TB),
		.valid_o		(valid_o_TB),
		.busy_o			(busy_o_TB),
		.output_RN_o	(output_o_TB)
	);

	tb_performance_monitor #(
		.OUTPUT_BITS	($bits(output_o_TB))
	) perf (
		.clk_i		(clk_i_TB),
		.valid_i	(valid_o_TB)
	);

endmodule

`default_nettype wire
