// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module REG #(
	parameter LENGTH = 1
)(
    input	logic				clk_i, 
	input	logic				nRST, 
	input	logic				EN,
    input	logic[LENGTH-1:0] 	IN,
    output	logic[LENGTH-1:0] 	OUT
) ;

always_ff @(posedge clk_i)
    if (~nRST)
        OUT <= 0;
    else begin	
        if (EN)	
		    OUT <= IN;
    end

endmodule
