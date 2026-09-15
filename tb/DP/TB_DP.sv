`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

`default_nettype none

module TB_DP #(
	parameter time						T_clk			= 10ns,
	parameter int unsigned				LENGTH_STATE	= 32,
	parameter int unsigned				LENGTH_SEED 	= 32,
	parameter logic [LENGTH_STATE-1:0]	A_INIT			= '0,
	parameter logic [LENGTH_STATE-1:0]	B_INIT			= '0,
	parameter int unsigned 				START_ODD		= 0,
	parameter logic [LENGTH_STATE-1:0]	A				= A_INIT,
	parameter logic [LENGTH_STATE-1:0]	B				= B_INIT,
	parameter int unsigned				start_odd		= START_ODD,
	parameter int unsigned				EXTRACTOR_CORE	= primitive_pkg::PRIMITIVE_CORE_KECCAK,
	parameter int unsigned				PRG_CORE		= primitive_pkg::PRIMITIVE_CORE_KECCAK
);

	// ===============================================================
	// Testbench Signals
	// ===============================================================
	logic						CLK_TB;
	logic						nRST_TB;
	logic						request_Reseed_TB;
	logic						request_RandomNumber_TB;
	logic	[LENGTH_SEED-1:0]	seed_TB;
	logic						ready_o_TB;
	logic						valid_o_TB;
	logic						busy_o_TB;
	logic	[LENGTH_SEED-1:0]	RandomNumber_TB;
	logic						inputs_end_TB;
	string						vcdFile;

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

		CLK_TB = 1'b0;
		$dumpfile(vcdFile);
		$dumpvars(0, TB_DP);
	end

	always #(T_clk/2) CLK_TB <= ~CLK_TB;

	// ===============================================================
	// Instance of the Unit Under Test
	// ===============================================================
	DP #(
		.LENGTH_STATE	(LENGTH_STATE),
		.LENGTH_SEED	(LENGTH_SEED),
		.A				(A),
		.B				(B),
		.start_odd		(start_odd),
		.EXTRACTOR_CORE	(EXTRACTOR_CORE),
		.PRG_CORE		(PRG_CORE)
	) UUT (
		.clk_i					(CLK_TB),
		.nRST					(nRST_TB),
		.request_Reseed			(request_Reseed_TB),
		.request_RandomNumber	(request_RandomNumber_TB),
		.seed					(seed_TB),
		.ready_o				(ready_o_TB),
		.valid_o				(valid_o_TB),
		.busy_o					(busy_o_TB),
		.RandomNumber			(RandomNumber_TB)
	);

	// ===============================================================
	// Modules used to generate and Check the Test signals for UUT!
	// ===============================================================

	// Generate Input Signals for the UUT
	data_maker #(
		.LENGTH_SEED	(LENGTH_SEED)
	) mkr (
		.clk_i					(CLK_TB),
		.ready_o				(ready_o_TB),
		.rst_n_i				(nRST_TB),
		.request_Reseed			(request_Reseed_TB),
		.request_RandomNumber	(request_RandomNumber_TB),
		.seed					(seed_TB),
		.inputs_end				(inputs_end_TB)
	);

	// Check Outputs of the UUT for correctness!
	data_sink #(
		.LENGTH_SEED	(LENGTH_SEED)
	) snk (
		.clk_i					(CLK_TB),
		.inputs_end				(inputs_end_TB),
		.request_RandomNumber	(request_RandomNumber_TB),
		.ready_o				(ready_o_TB),
		.valid_o				(valid_o_TB),
		.busy_o					(busy_o_TB),
		.RandomNumber			(RandomNumber_TB)
	);

	tb_performance_monitor #(
		.OUTPUT_BITS	($bits(RandomNumber_TB))
	) perf (
		.clk_i		(CLK_TB),
		.valid_i	(valid_o_TB)
	);

endmodule

`default_nettype wire
