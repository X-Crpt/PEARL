`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

`default_nettype none

module tb_performance_monitor #(
	parameter int unsigned OUTPUT_BITS = 1
) (
	input logic clk_i,
	input logic valid_i
);

	int fd_perf;
	int unsigned cycle_count;
	int unsigned valid_count;
	string perfFile;
	real cycles_per_generation;
	real bits_per_cycle;

	initial begin
		perfFile = "";
		fd_perf = 0;
		cycle_count = 0;
		valid_count = 0;
		cycles_per_generation = 0.0;
		bits_per_cycle = 0.0;

		$value$plusargs("PERF_FILE=%s", perfFile);

		if (perfFile != "") begin
			fd_perf = $fopen(perfFile, "w");
			if (fd_perf == 0) begin
				$fatal(1, "Cannot open performance report file in write mode: %s", perfFile);
			end
		end
	end

	always_ff @(posedge clk_i) begin
		cycle_count <= cycle_count + 1;
		if (valid_i) begin
			valid_count <= valid_count + 1;
		end
	end

	final begin
		if ((cycle_count != 0) && (valid_count != 0)) begin
			cycles_per_generation = (1.0 * cycle_count) / valid_count;
			bits_per_cycle = (1.0 * OUTPUT_BITS * valid_count) / cycle_count;
		end

		$display("-------------------- Performance Summary -------------------");
		$display("Output bits per generation: %0d", OUTPUT_BITS);
		$display("Cycles: %0d", cycle_count);
		$display("Valid outputs: %0d", valid_count);
		$display("Cycles per generation: %.6f", cycles_per_generation);
		$display("Bits per cycle: %.6f", bits_per_cycle);
		$display("-----------------------------------------------------------");

		if (fd_perf != 0) begin
			$fwrite(fd_perf, "output_bits,cycles,valid_outputs,cycles_per_generation,bits_per_cycle\n");
			$fwrite(fd_perf, "%0d,%0d,%0d,%.6f,%.6f\n",
				OUTPUT_BITS,
				cycle_count,
				valid_count,
				cycles_per_generation,
				bits_per_cycle
			);
			$fclose(fd_perf);
		end
	end

endmodule

`default_nettype wire
