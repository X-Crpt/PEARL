// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module RightShifter #(
	parameter AMOUNT = 1
	)(	
	input logic[31:0] IN,
	output logic[31:0] OUT
	) ;

always_comb begin
	
	OUT = (IN >> AMOUNT);

	end
endmodule
