`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

`default_nettype none

module TB_AES_128;

	// ===============================================================
	// Testbench Signals and constants
	// ===============================================================
	localparam time T_clk = 10ns;

	logic				CLK_TB;
	logic				RST_n_TB;
	logic				valid_i_TB;
	logic [127 : 0]		input_i_TB;
	logic [127 : 0]		key_i_TB;
	logic				inputs_end_TB;
	logic [127 : 0]		output_o_TB;
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

		CLK_TB = 1'b0;
		$dumpfile(vcdFile);
		$dumpvars(0, TB_AES_128);
	end

	always #(T_clk/2) CLK_TB <= ~CLK_TB;

	// ===============================================================
	// Instance of the Unit Under Test
	// ===============================================================
	AES_128_pipe UUT (
		.CLK		(CLK_TB),
		.RST_n		(RST_n_TB),
		.valid_i	(valid_i_TB),
		.input_i	(input_i_TB),
		.key_i		(key_i_TB),
		.output_o	(output_o_TB),
		.valid_o	(valid_o_TB),
		.busy_o		(busy_o_TB)
	);

	// ===============================================================
	// Modules used to generate and Check the Test signals for UUT!
	// ===============================================================

	// Generate Input Signals for the UUT
	data_maker mkr (
		.RST_n		(RST_n_TB),
		.valid_i	(valid_i_TB),
		.input_i	(input_i_TB),
		.key_i		(key_i_TB),
		.inputs_end	(inputs_end_TB)
	);

	// Check Outputs of the UUT for correctness!
	data_sink snk (
		.CLK		(CLK_TB),
		.inputs_end	(inputs_end_TB),
		.valid_o	(valid_o_TB),
		.busy_o		(busy_o_TB),
		.output_o	(output_o_TB)
	);

endmodule

`default_nettype wire
