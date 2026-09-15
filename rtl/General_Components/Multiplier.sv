// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module Multiplier 
#( parameter LENGTH = 2
) (
	input logic[LENGTH-1:0] A,B,
	output logic[2*(LENGTH-1):0] M
	) ;

always_comb 

	M = A * B;

endmodule
