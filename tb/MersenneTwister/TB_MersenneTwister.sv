`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

`default_nettype none

module TB_MersenneTwister #(
	parameter time			T_clk			= 10ns,
	parameter int unsigned	LENGTH			= 32,
	parameter int unsigned	RESEED_PERIOD	= 20
);

	logic					CLK_TB;
	logic					nRST_TB;
	logic					request_RandomNumber_TB;
	logic					request_Reseed_TB;
	logic	[LENGTH-1:0]	seed_TB;
	//logic					DONE_TB;
	logic					ready_o_TB;
	logic					valid_o_TB;
	logic					busy_o_TB;
	logic	[LENGTH-1:0]	RandomNumber_TB;
	
	
	logic			inputs_end_TB;
	string			vcdFile;

	initial begin
		// Retrive the VCD file path from Input Argument, and throw an error if
		// this path is not passed to the Testbench
		vcdFile = "";
		$value$plusargs("VCD_FILE=%s", vcdFile);
		if (vcdFile == "") begin
			$fatal(1, "Missing +VCD_FILE plusarg for VCD dump path");
		end

		// Setup the VCD Dump
		$dumpfile(vcdFile);
		$dumpvars(0, TB_MersenneTwister);

		// Initailize the states of the TB
		CLK_TB = 1'b0;
	end

	always #(T_clk/2) CLK_TB <= ~CLK_TB;

	MersenneTwister #(
		.LENGTH	(LENGTH)
	) UUT (
		.clk_i					(CLK_TB),
		.nRST					(nRST_TB),
		.request_RandomNumber	(request_RandomNumber_TB),
		.request_Reseed			(request_Reseed_TB),
		.seed					(seed_TB),
		//.DONE					(DONE_TB),
		.ready_o				(ready_o_TB),
		.valid_o				(valid_o_TB),
		.busy_o					(busy_o_TB),
		.RandomNumber			(RandomNumber_TB)
	);

	data_maker #(
		.LENGTH	(LENGTH)
	) mkr (
		.clk_i					(CLK_TB),
		.ready_o				(ready_o_TB),
		.rst_n_i				(nRST_TB),
		.request_RandomNumber	(request_RandomNumber_TB),
		.request_Reseed			(request_Reseed_TB),
		.seed					(seed_TB),
		.inputs_end				(inputs_end_TB)
	);

	data_sink #(
		.LENGTH	(LENGTH)
	) snk (
		.clk_i					(CLK_TB),
		.inputs_end				(inputs_end_TB),
		.request_RandomNumber	(request_RandomNumber_TB),
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
