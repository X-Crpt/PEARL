`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module data_maker #(
	parameter int unsigned SEEDLEN = 256
) (
	input	logic				clk_i,
	input	logic				ready_o,
	output 	logic 				rst_n_i,
	output 	logic 				request_RN_i,
	output 	logic [SEEDLEN-1:0]	entropy_i,
	output	logic				inputs_end
);

	int fd;										// File descriptor, used to access the file
	int unsigned line_idx;						// Index of the current line read from the input vector file
	logic [SEEDLEN-1:0] entropy_input_i_vect;	// Variable used to retrieve entropy data from the file
	logic has_entropy_pending;					// Indicates if entropy_input_i_vect contains unread entropy
	logic eof_reached;							// Indicates if input file reached EOF
	logic first_cycle_done;						// Used to force exactly one reset cycle at start
	string inputFile;

	initial begin
		string line_init;
		int scan_status_init;

		// Set safe default values on outputs
		rst_n_i			= 1'b0;
		request_RN_i	= 1'b0;
		entropy_i	= '0;
		inputs_end = 1'b0;

		// Get the input vector file path from command line
		$value$plusargs("INPUT_VECT_FILE=%s", inputFile);
		$display("INPUT FILE PATH: %s", inputFile);

		fd = $fopen(inputFile, "r");
		if (fd == 0) begin
			$fatal(1, "Cannot open input file: %s", inputFile);
		end

		has_entropy_pending = 1'b0;
		eof_reached = 1'b0;
		first_cycle_done = 1'b0;
		line_idx = 0;

		// Preload the first entropy value before reset is released, so the UUT initialization
		// can consume the first input vector instead of all-zeros.
		scan_status_init = $fgets(line_init, fd);
		if (scan_status_init != 0) begin
			scan_status_init = $sscanf(line_init, "%h", entropy_input_i_vect);
		end

		if (scan_status_init == 1) begin
			entropy_i		= entropy_input_i_vect;
			has_entropy_pending	= 1'b1;
			line_idx			= 1;
		end else if ((scan_status_init == -1) || $feof(fd)) begin
			eof_reached = 1'b1;
		end else begin
			$fatal(
				1,
				"Input vector format error at line %0d in file %s. Expected: <entropy_i>",
				1,
				inputFile
			);
		end
	end

	always_ff @(posedge clk_i) begin
		string line;
		int scan_status_local;

		// First cycle: force reset
		if (!first_cycle_done) begin
			// Set the signals necessary to initilize the unit (basically just reset the unit at startup)
			rst_n_i <= 1'b0;
			request_RN_i <= 1'b0;

			// Signal that the first cycle intialization is done, now the unit can accept inputs from the 
			// input vector file
			first_cycle_done <= 1'b1;
		end else begin
			// After first cycle, keep reset deasserted forever
			rst_n_i <= 1'b1;

			// If no entropy is buffered and file is not ended, read next entropy value
			if (!has_entropy_pending && !eof_reached) begin
				scan_status_local = $fgets(line, fd);
				if (scan_status_local != 0) begin
					scan_status_local = $sscanf(line, "%h", entropy_input_i_vect);
				end

				if (scan_status_local == 1) begin
					has_entropy_pending <= 1'b1;
					line_idx <= line_idx + 1;
				end else if ((scan_status_local == -1) || $feof(fd)) begin
					eof_reached <= 1'b1;
				end else begin
					$fatal(
						1,
						"Input vector format error at line %0d in file %s. Expected: <entropy_i>",
						line_idx + 1,
						inputFile
					);
				end
			end

			// Request a new random number automatically whenever the unit is ready and an entropy value is available
			if (ready_o && has_entropy_pending) begin
				request_RN_i <= 1'b1;
				entropy_i <= entropy_input_i_vect;
				has_entropy_pending <= 1'b0;
			end else begin
				request_RN_i <= 1'b0;
			end

			// Signal end only when file ended and no more entropy is pending
			if (eof_reached && !has_entropy_pending) begin
				inputs_end <= 1'b1;
				if (fd != 0) begin
					$fclose(fd);
					fd <= 0;
				end
			end
		end
	end

endmodule
