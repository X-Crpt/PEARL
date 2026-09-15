`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module data_maker #(
	parameter int unsigned LENGTH = 32
) (
	input	logic					clk_i,
	input	logic					ready_o,
	output	logic					rst_n_i,
	output	logic					request_RandomNumber,
	output	logic					request_Reseed,
	output	logic	[LENGTH-1:0]	seed,
	output	logic					inputs_end
);

	// States of the "Data Maker Unit"
	logic 				eof_reached;
	logic				has_pending_input;
	logic				pending_request_Reseed;
	logic [LENGTH-1:0]	pending_seed;
	int unsigned 		line_idx;

	int fd;
	string inputFile;
	initial begin
		$value$plusargs("INPUT_VECT_FILE=%s", inputFile);
		$display("INPUT FILE PATH: %s", inputFile);

		fd = $fopen(inputFile, "r");
		if (fd == 0) begin
			$fatal(1, "Cannot open input file: %s", inputFile);
		end

		// Initialize all the "Data Maker" outputs
		// Match Lorenzo's burst TB: keep reset low at time 0, then release it
		// before the first clock edge so the DUT starts from its initial state.
		rst_n_i 				= 1'b0;
		request_Reseed			= 1'b0;
		request_RandomNumber	= 1'b0;
		seed					= LENGTH'(32'h7833794e);
		inputs_end				= 1'b0;

		// Initialize the internal states of the "Data Maker"
		eof_reached				= 1'b0;
		has_pending_input		= 1'b0;
		pending_request_Reseed	= 1'b0;
		pending_seed			= '0;
		line_idx 				= 0;

		//#2 rst_n_i				= 1'b1;
	end

	assign request_Reseed		= has_pending_input && pending_request_Reseed;
	assign request_RandomNumber	= has_pending_input && !pending_request_Reseed;
	assign seed					= pending_seed;

	always_ff @(posedge clk_i) begin
		string 				line;
		logic [LENGTH-1:0]	seed_hex;
		int 				scan_status;
		int unsigned 		request_Reseed_int;

 		if (has_pending_input && ready_o) begin
 			has_pending_input <= 1'b0;
 		end

		rst_n_i				<= 1'b1;
 
 		// Read a new Input Vector Line only when there is no buffered request.
 		if (!has_pending_input && !eof_reached) begin 
 			// Read and parse the current Input Vector line.
 			// The format is: <request_Reseed> <seed>
 			scan_status = $fgets(line, fd);
 			if (scan_status != 0) begin
 				scan_status = $sscanf(line, "%d %h", request_Reseed_int, seed_hex);
 			end
 
 			// Check if the Expected number of fields are read from the Input Vector Line
 			if (scan_status == 2) begin
 				pending_request_Reseed	<= (request_Reseed_int != 0);
 				pending_seed			<= seed_hex;
 				has_pending_input		<= 1'b1;
 				line_idx				<= line_idx + 1;
 
 			// Check if the EOF is reached, and in that case close the file and exit
 			end else if ((scan_status == -1) || $feof(fd)) begin
 				eof_reached	<= 1'b1;
 				inputs_end	<= 1'b1;
 				if (fd != 0) begin
 					$fclose(fd);
 					fd <= 0;
 				end
 
 			// Check if something un-expected was read from the Current Line of the input Vector
 			end else begin
 				$fatal(	1,
 						"Input vector format error at line %0d in file %s. Expected: <request_Reseed> <seed>",
 						line_idx + 1,
 						inputFile
 				);
 			end
 		end
	end

endmodule
