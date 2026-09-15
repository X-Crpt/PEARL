`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module data_sink (
	input	logic			CLK,
	input	logic			inputs_end,
	input	logic			valid_o,
	input	logic			busy_o,
	input	logic [127 : 0]	output_o
);

	int fd_gold;						// File descriptor for the Golden Model Outputs
	int fd_log;							// File descriptor for saving the HDL outputs
	int unsigned idx;					// Index of the current output cycle
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

		fd_gold = $fopen(goldFile, "r");
		if (fd_gold == 0) begin
			$fatal(1, "Cannot open Golden Model output file in read mode: %s", goldFile);
		end

		fd_log = $fopen(logFile, "w");
		if (fd_log == 0) begin
			$fatal(1, "Cannot open HDL output file in write mode: %s", logFile);
		end

		// Initialize variables
		idx   = 0;
		n_err = 0;
	end

	// Compare outputs cycle-by-cycle.
	// Golden output vector format per line:
	// valid_o busy_o output_o
	always @(posedge CLK) begin
		int unsigned cycle_errs;
		logic valid_o_gold;
		logic busy_o_gold;
		logic [127 : 0] output_o_gold;

		cycle_errs = 0;

		if ($fscanf(fd_gold, "%b %b %h\n", valid_o_gold, busy_o_gold, output_o_gold) != 3) begin
			$fatal(1, "Golden output file ended too early at idx=%0d", idx);
		end

		// Save current HDL outputs cycle-by-cycle
		$fwrite(fd_log, "%b %b %032h\n", valid_o, busy_o, output_o);
		$fflush(fd_log);

		// Compare valid_o pin
		if (valid_o != valid_o_gold) begin
			cycle_errs++;
			$warning("Mismatch valid_o at idx=%0d", idx);
			$display("\t-> GoldModel = \t%b", valid_o_gold);
			$display("\t-> HDL       = \t%b", valid_o);
		end

		// Compare busy_o pin
		if (busy_o != busy_o_gold) begin
			cycle_errs++;
			$warning("Mismatch busy_o at idx=%0d", idx);
			$display("\t-> GoldModel = \t%b", busy_o_gold);
			$display("\t-> HDL       = \t%b", busy_o);
		end

		// Compare output_o pin only if the output is valid
		if (valid_o) begin	
			if (output_o != output_o_gold) begin
				cycle_errs++;
				$warning("Mismatch output_o at idx=%0d", idx);
				$display("\t-> GoldModel = \t0x%032h", output_o_gold);
				$display("\t-> HDL       = \t0x%032h", output_o);
			end
		end

		

		n_err <= n_err + cycle_errs;
		idx   <= idx + 1;

		// End simulation only after all inputs are sent and pipeline is empty
		if (inputs_end && !busy_o) begin
			$finish;
		end
	end

	final begin
		if (fd_gold != 0) begin
			$fclose(fd_gold);
		end
		if (fd_log != 0) begin
			$fclose(fd_log);
		end

		$display("---------------------- Test Summary ------------------------");
		if (idx == 0) begin
			$display("\nTest result: FAIL  (0 patterns checked)\n");
		end else if (n_err == 0) begin
			$display("\nTest result: ✅ PASS (Patterns checked = %0d)\n", idx);
		end else begin
			$display("\nTest result: FAIL  (errors=%0d)\n", n_err);
		end
		$display("-----------------------------------------------------------");
	end

endmodule
