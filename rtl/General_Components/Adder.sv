// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module Adder 
#( parameter LENGTH = 2
) (
	input logic[LENGTH-1:0] A,B,
	output logic[LENGTH:0] S
	);

always_comb
	
	S = A + B;

endmodule
