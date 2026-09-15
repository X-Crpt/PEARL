`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Small synchronous FIFO.
//
// The module is implemented as a circular buffer in register/memory space: write and read pointers
// move independently and wrap at the end of the storage depth. A counter tracks the number of
// occupied entries and drives the status flags. Push and pop can happen in the same cycle; in that
// case the pointers are both advanced and the occupancy count stays unchanged.
//
// From a usage point of view, `push_i` requests insertion of `data_i` in the FIFO, `pop_i` consumes
// the current head element, `data_o` always exposes the current head, and `full_o` indicates when
// a push alone cannot be accepted. A push is still allowed when `full_o` is high only if a pop
// happens in the same cycle.
// ==============================================================================================

module FIFO #(
	parameter int unsigned DATA_WIDTH	= 32,
	parameter int unsigned DEPTH		= 4
) (
	input	logic						clk_i,
	input	logic						rst_n_i,
	input	logic						push_i,		// Control input that tells the FIFO that a new value (from data_i) is available.
	input	logic						pop_i,		// Control input that tells the FIFO to remove the current top value and move to the next one.
	input	logic [(DATA_WIDTH-1) : 0]	data_i,		// Input data bus. It is used only when push_i is HIGH.
	output	logic [(DATA_WIDTH-1) : 0]	data_o,		// Output data bus. It always contains the current top value of the FIFO.
	output	logic						empty_o,	// Control output that indicates that the FIFO is empty
	output	logic						full_o		// Control output that indicates that the FIFO is full
);

	localparam int unsigned PTR_WIDTH	= $clog2(DEPTH);		// Number of bits needed for both FIFO pointers (read and write pointers).
	localparam int unsigned COUNT_W		= $clog2(DEPTH + 1);	// Number of bits needed to count entries from 0 to DEPTH.

	logic [DATA_WIDTH-1 : 0] 	fifo_mem [0 : DEPTH-1];		// Main FIFO circular buffer ("DEPTH" cells, each one "DATA_WIDTH" bits wide).
	logic [PTR_WIDTH-1:0]		read_ptr;					// Pointer to the current head element to be read/popped.
	logic [PTR_WIDTH-1:0]		write_ptr;					// Pointer to the next location to be written/pushed.
	logic [COUNT_W-1:0]			count;						// Current number of valid elements stored in the FIFO.											
	logic do_push;
	logic do_pop;

	// Input parameter checks.
	// These checks are simulation-time checks and are useful to detect wrong module usage early.
	initial begin
		assert (DEPTH >= 1)
			else $fatal(1, "DEPTH must be >= 1");
		assert (DATA_WIDTH >= 1)
			else $fatal(1, "DATA_WIDTH must be >= 1");
	end

	// Function that increments a pointer with wrap-around at DEPTH.
	function automatic [PTR_WIDTH-1:0] ptr_inc(input [PTR_WIDTH-1:0] ptr_i);
		if (ptr_i == PTR_WIDTH'(DEPTH-1)) begin
			ptr_inc = '0;
		end else begin
			ptr_inc = ptr_i + PTR_WIDTH'(1);
		end
	endfunction

	

	// Head element is exposed combinationally.
	assign data_o = fifo_mem[read_ptr];

	// Define the combinational conditions in which pop and push operations are allowed.
	assign empty_o	= (count == '0);				
	assign full_o	= (count == COUNT_W'(DEPTH));
	assign do_pop	= pop_i && !empty_o;				// Pop is performed when requested and when the FIFO is not empty_o.
	assign do_push	= push_i && (!full_o || do_pop);	// Push is performed when requested and when FIFO is not full (or a pop happens in the same cycle).

	// Execute FIFO operations sequentially.
	always_ff @(posedge clk_i) begin
		if (!rst_n_i) begin
			// If reset is active, reset all internal FIFO state.
			read_ptr	<= '0;
			write_ptr	<= '0;
			count		<= '0;
		end else begin
			// If push is requested, execute it.
			if (do_push) begin
				fifo_mem[write_ptr]	<= data_i;				// Save the new data in the location pointed by write_ptr.
				write_ptr 			<= ptr_inc(write_ptr);	// Advance the write pointer.
			end

			// If pop is requested, execute it.
			if (do_pop) begin
				read_ptr <= ptr_inc(read_ptr);				// Advance the read pointer (data is already exposed combinationally).
			end

			// Update the variable that counts the number of stored elements.
			case ({do_push, do_pop})
				// Case: push active, pop inactive.
				2'b10: count <= count + 1'b1;

				// Case: pop active, push inactive.
				2'b01: count <= count - 1'b1;

				// Default case (all other combinations): the number of stored elements stays constant.
				default: count <= count;
			endcase
		end
	end

endmodule
