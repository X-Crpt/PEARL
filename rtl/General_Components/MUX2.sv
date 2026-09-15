// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module MUX2
#( parameter LENGTH = 1)
(
    input logic[(LENGTH-1):0]	IN_0 ,
    input logic[(LENGTH-1):0]	IN_1 ,
    input logic					SEL ,
    output logic[(LENGTH-1):0]	OUT
) ;
always_comb begin
    if (SEL == 0)
        OUT = IN_0;
    else
        OUT = IN_1;
    end 
endmodule
