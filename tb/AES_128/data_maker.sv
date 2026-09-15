`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module data_maker (
	output 	logic 				RST_n,
	output 	logic 				valid_i,
	output 	logic [127 : 0] 	input_i,
	output 	logic [127 : 0] 	key_i,
	output	logic				inputs_end
);

	int fd;										// File descriptor, used to access the file
	int scan_status;								// Number of fields correctly read from current line
	int unsigned line_idx;							// Index of the current line read from the input vector file
	logic rst_n_vect, valid_i_vect;				// Variables used to retrive 1-bit data from the file
	logic [127 : 0] input_i_vect, key_i_vect;	// Variables used to retrive 128-bit data from the file
	parameter time T_read = 10ns;				// Amount of time after which a new data is read from input vector file
	parameter time T_offset = 1ns;				// Initial time offset before starting to apply vectors
	string inputFile;

	initial begin
		// Set safe default values on outputs
		RST_n	= 1'b0;
		valid_i	= 1'b0;
		input_i = '0;
		key_i	= '0;
		inputs_end = 1'b0;

		// Get the input vector file path from command line
		$value$plusargs("INPUT_VECT_FILE=%s", inputFile);

		fd = $fopen(inputFile, "r");
		if (fd == 0) begin
			$fatal(1, "Cannot open input file: %s", inputFile);
		end

		$display ("HDL Simulation start.");
		#T_offset;
		line_idx = 0;

		// Retrive data from the input vector file up until I reach the end of the file
		while (1) begin
			// Input vector format per line: RST_n valid_i input_i key_i
			scan_status = $fscanf(fd, "%b %b %h %h\n", rst_n_vect, valid_i_vect, input_i_vect, key_i_vect);

			if (scan_status == 4) begin
				// Assign the read values into the output port of the data maker 
				// (basically to the input of the UUT)
				RST_n	= rst_n_vect;
				valid_i	= valid_i_vect;
				input_i = input_i_vect;
				key_i	= key_i_vect;
				line_idx++;

				// Wait for a pre-defined amount of time before reading/applying next vector
				#T_read;
			end else if ((scan_status == -1) || $feof(fd)) begin
				// End Of File reached
				break;
			end else begin
				$fatal(
					1,
					"Input vector format error at line %0d in file %s. Expected: <RST_n> <valid_i> <input_i> <key_i>",
					line_idx + 1,
					inputFile
				);
			end
		end

		// Close the file!
		valid_i = 1'b0;
		inputs_end = 1'b1;
		$fclose(fd);
	end

endmodule
