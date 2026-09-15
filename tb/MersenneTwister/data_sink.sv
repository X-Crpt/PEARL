`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module data_sink #(
	parameter int unsigned LENGTH = 32
) (
	input	logic			clk_i,
	input	logic			inputs_end,
	input	logic			request_RandomNumber,
	input	logic			valid_o,
	input	logic			busy_o,
	input	logic	[LENGTH-1:0]	RandomNumber
);

	// Internal states of the "Data Sink Unit"
	int unsigned	cycle_idx;
	int unsigned	valid_idx;
	int unsigned	n_err;
	
	string goldFile, logFile;
	int fd_gold;
	int fd_log;
	initial begin
		goldFile = "";
		logFile  = "";

		// Retrive the paths for the "Golden Model Output File" and "HDL Model Output File"
		// from the System Verilog input arguments
		$value$plusargs("GOLD_VECT_FILE=%s", goldFile);
		$value$plusargs("HDL_VECT_FILE=%s", logFile);

		// Display on the terminal the Paths received as Input Arguments
		// $display("OUTPUT GOLDEN MODEL FILE PATH: %s", goldFile);
		// $display("OUTPUT HDL FILE PATH: %s", logFile);

		// Open the files, and throw fatal errors in case of some errors
		fd_gold = $fopen(goldFile, "r");
		if (fd_gold == 0) begin
			$fatal(1, "Cannot open Golden Model output file in read mode: %s", goldFile);
		end

		fd_log = $fopen(logFile, "w");
		if (fd_log == 0) begin
			$fatal(1, "Cannot open HDL output file in write mode: %s", logFile);
		end

		// Initialize the states of the "Data Sink Unit"
		cycle_idx			= 0;	// Index of the current Clock Cycle from the start of the TB
		valid_idx			= 0;	// Number of Valid Inputs fed to the DUT from the start of the TB
		n_err				= 0;	// Counter of errors detected during the test (mismatch between the Golden Model and the HDL outputs)
	end

	always_ff @(posedge clk_i) begin
		int unsigned 					cycle_errs;
		logic			[LENGTH-1:0]	RandomNumber_gold;
		int								scan_status;

		cycle_errs = 0;

		if (valid_o) begin
			$fwrite(fd_log, "%08h\n", RandomNumber);
			$fflush(fd_log);
			scan_status = $fscanf(fd_gold, "%h\n", RandomNumber_gold);
			if (scan_status != 1) begin
				cycle_errs++;
				$display("[TB][ERR][cycle %0d] Golden output file has no line for valid output index %0d.", cycle_idx, valid_idx);
			end else if (RandomNumber != RandomNumber_gold) begin
				cycle_errs++;
				$display("[TB][ERR][cycle %0d] Mismatch RandomNumber at valid index %0d.", cycle_idx, valid_idx);
				$display("\t-> GoldModel = 0x%08h", RandomNumber_gold);
				$display("\t-> HDL       = 0x%08h", RandomNumber);
			end
			valid_idx <= valid_idx + 1;
		end

		n_err <= n_err + cycle_errs;
		cycle_idx <= cycle_idx + 1;

		if (inputs_end && !busy_o) begin
			$finish;
		end
	end

	final begin
		logic [LENGTH-1:0] trailing_gold_value;
		int trailing_scan_status;

		if (fd_gold != 0) begin
			trailing_scan_status = $fscanf(fd_gold, "%h\n", trailing_gold_value);
			if (trailing_scan_status == 1) begin
				$display("[TB][WARN] Golden output file contains extra unmatched lines after simulation end. First extra value = 0x%08h", trailing_gold_value);
			end
			$fclose(fd_gold);
		end
		if (fd_log != 0) begin
			$fclose(fd_log);
		end

		$display("---------------------- Test Summary ------------------------");
		if (cycle_idx == 0) begin
			$display("\nTest result: FAIL  (0 patterns checked)\n");
		end else if (n_err == 0) begin
			$display("\nTest result: PASS  (Cycles = %0d, Valid outputs = %0d)\n", cycle_idx, valid_idx);
		end else begin
			$display("\nTest result: FAIL  (errors=%0d, Cycles = %0d, Valid outputs = %0d)\n", n_err, cycle_idx, valid_idx);
		end
		$display("-----------------------------------------------------------");
	end

endmodule
