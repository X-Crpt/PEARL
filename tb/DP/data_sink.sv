`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module data_sink #(
	parameter int unsigned LENGTH_SEED = 128
) (
	input	logic						clk_i,
	input	logic						inputs_end,
	input	logic						request_RandomNumber,
	input	logic						ready_o,
	input	logic						valid_o,
	input	logic						busy_o,
	input	logic	[LENGTH_SEED-1:0]	RandomNumber
);

	int fd_gold;						// File descriptor for the Golden Model Outputs
	int fd_log;							// File descriptor for saving the HDL outputs
	int unsigned cycle_idx;				// Index of the current simulation cycle
	int unsigned valid_idx;				// Index of valid outputs observed at RTL output
	int unsigned accepted_req_count;	// Number of accepted requests not yet matched by a valid_o
	int unsigned n_err;					// Counter for the total number of errors
	string goldFile, logFile;

	initial begin
		goldFile = "";
		logFile  = "";

		// Allow file paths to be passed from command line
		// Example: +GOLD_VECT_FILE=./SIM/AES_128/vectors/outputVect_gold.txt
		// Example: +HDL_VECT_FILE=./SIM/AES_128/vectors/outputVect_hdl.txt
		$value$plusargs("GOLD_VECT_FILE=%s", goldFile);
		$value$plusargs("HDL_VECT_FILE=%s", logFile);

		$display("OUTPUT GOLDEN MODEL FILE PATH: %s", goldFile);
		$display("OUTPUT HDL FILE PATH: %s", logFile);

		fd_gold = $fopen(goldFile, "r");
		if (fd_gold == 0) begin
			$fatal(1, "Cannot open Golden Model output file in read mode: %s", goldFile);
		end

		fd_log = $fopen(logFile, "w");
		if (fd_log == 0) begin
			$fatal(1, "Cannot open HDL output file in write mode: %s", logFile);
		end

		// Initialize variables
		cycle_idx = 0;
		valid_idx = 0;
		accepted_req_count = 0;
		n_err = 0;
	end

	// Advanced sink/scoreboard behavior:
	// 1) Track accepted random-number requests: request_RandomNumber && ready_o.
	// 2) Compare RandomNumber against Golden Model only when valid_o is high.
	// 3) Check protocol consistency on control pins and report clear debug errors.
	always @(posedge clk_i) begin
		int unsigned cycle_errs;
		int signed pending_after_accept;
		logic [LENGTH_SEED-1:0] RandomNumber_gold;
		int scan_status;
		bit request_accepted;

		cycle_errs = 0;
		request_accepted = (request_RandomNumber && ready_o);
		pending_after_accept = accepted_req_count + (request_accepted ? 1 : 0);

		// Protocol check #2: a valid output requires at least one pending accepted request
		if (valid_o && (pending_after_accept == 0)) begin
			cycle_errs++;
			$display("[TB][ERR][cycle %0d] valid_o asserted with no pending accepted request.", cycle_idx);
		end

		// Compare RandomNumber only when valid_o is asserted
		if (valid_o) begin
			// Save only generated random numbers (same format as Golden Model: one HEX value per valid output)
			$fwrite(fd_log, "%0h\n", RandomNumber);
			$fflush(fd_log);

			scan_status = $fscanf(fd_gold, "%h\n", RandomNumber_gold);
			if (scan_status != 1) begin
				cycle_errs++;
				$display("[TB][ERR][cycle %0d] Golden output file has no line for valid output index %0d.", cycle_idx, valid_idx);
			end else if (RandomNumber != RandomNumber_gold) begin
				cycle_errs++;
				$display("[TB][ERR][cycle %0d] Mismatch RandomNumber at valid index %0d.", cycle_idx, valid_idx);
				$display("\t-> GoldModel = 0x%0h", RandomNumber_gold);
				$display("\t-> HDL       = 0x%0h", RandomNumber);
			end
			valid_idx <= valid_idx + 1;
			if (pending_after_accept > 0) begin
				pending_after_accept--;
			end
		end

		if (pending_after_accept < 0) begin
			pending_after_accept = 0;
		end

		accepted_req_count <= pending_after_accept;
		n_err <= n_err + cycle_errs;
		cycle_idx <= cycle_idx + 1;

		// End simulation only after all inputs are sent and pipeline is empty
		if (inputs_end && (accepted_req_count == 0) && !busy_o) begin
			$finish;
		end
	end

	final begin
		logic [LENGTH_SEED-1:0] trailing_gold_value;
		int trailing_scan_status;

		if (fd_gold != 0) begin
			// Optional consistency check: if extra golden lines remain, warn to ease debug
			trailing_scan_status = $fscanf(fd_gold, "%h\n", trailing_gold_value);
			if (trailing_scan_status == 1) begin
				$display("[TB][WARN] Golden output file contains extra unmatched lines after simulation end. First extra value = 0x%0h", trailing_gold_value);
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
