`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module data_maker #(
	parameter int unsigned LENGTH_SEED = 128
) (
	input	logic						clk_i,
	input	logic						ready_o,
	output	logic						rst_n_i,
	output	logic						request_Reseed,
	output	logic						request_RandomNumber,
	output	logic	[LENGTH_SEED-1:0]	seed,
	output	logic						inputs_end
);

	// States of the "Data Maker Unit"
	int unsigned line_idx;
	logic request_reseed_vect;
	logic [LENGTH_SEED-1:0] seed_vect;
	logic has_input_pending;
	logic eof_reached;
	logic first_cycle_done;
	
	int fd;
	string inputFile;
	initial begin
		rst_n_i = 1'b0;
		request_Reseed = 1'b0;
		request_RandomNumber = 1'b0;
		seed = '0;
		inputs_end = 1'b0;

		$value$plusargs("INPUT_VECT_FILE=%s", inputFile);
		$display("INPUT FILE PATH: %s", inputFile);

		fd = $fopen(inputFile, "r");
		if (fd == 0) begin
			$fatal(1, "Cannot open input file: %s", inputFile);
		end

		line_idx = 0;
		request_reseed_vect = 1'b0;
		seed_vect = '0;
		has_input_pending = 1'b0;
		eof_reached = 1'b0;
		first_cycle_done = 1'b0;
	end

	always_ff @(posedge clk_i) begin
		string line;
		int scan_status;
		int unsigned request_reseed_int;

		if (!first_cycle_done) begin
			rst_n_i <= 1'b0;
			request_Reseed <= 1'b0;
			request_RandomNumber <= 1'b0;
			first_cycle_done <= 1'b1;
		end else begin
			rst_n_i <= 1'b1;
			request_Reseed <= 1'b0;
			request_RandomNumber <= 1'b0;

			if (!has_input_pending && !eof_reached) begin
				scan_status = $fgets(line, fd);
				if (scan_status != 0) begin
					scan_status = $sscanf(line, "%d %h", request_reseed_int, seed_vect);
				end

				if (scan_status == 2) begin
					request_reseed_vect <= (request_reseed_int != 0);
					has_input_pending <= 1'b1;
					line_idx <= line_idx + 1;
				end else if ((scan_status == -1) || $feof(fd)) begin
					eof_reached <= 1'b1;
				end else begin
					$fatal(
						1,
						"Input vector format error at line %0d in file %s. Expected: <request_Reseed> <seed>",
						line_idx + 1,
						inputFile
					);
				end
			end

			if (ready_o && has_input_pending) begin
				request_Reseed <= request_reseed_vect;
				request_RandomNumber <= !request_reseed_vect;
				seed <= seed_vect;
				has_input_pending <= 1'b0;
			end

			if (eof_reached && !has_input_pending) begin
				inputs_end <= 1'b1;
				if (fd != 0) begin
					$fclose(fd);
					fd <= 0;
				end
			end
		end
	end

endmodule
