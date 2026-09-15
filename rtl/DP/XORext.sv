// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module XORext #(parameter
    //LENGTH = 32,
    k = 24,
    r = 8
) (
    input logic clk_i,nRST,Ext_start,
    input logic[k-1:0] C,
    input logic[r-1:0] K,
    output logic Ext_Done,
    output logic[k-1:0] X,
    output logic[r-1:0] Kout
);

logic[k+r:0] temp;
logic[k-1:0] Xtemp;
logic[r-1:0] Ktemp;

always_ff @(posedge clk_i) begin 
if (~nRST) begin
        Ext_Done = 0;
        X = 0;
        Kout = 0;
        if (Ext_start) begin 
            Ext_Done = 1;
            X = Xtemp;
            Kout = Ktemp;
        end
        else 
            Ext_Done = 0;
end
end

initial begin 
    for (int i = 0; i < k+r; i++) begin
        temp[2*i] = C[i];
        temp[2*i+1] = K[i];
    end
    temp[k+r] = 0;
    
    for (int q = 0; q < k; q++) begin 
        Xtemp[q] = temp[q] ^ temp[q+1];
    end

    for (int y = 0; y < r; y++) begin 
        Ktemp[y] = temp[y+k] ^ temp[y+k+1];
    end

end

endmodule



