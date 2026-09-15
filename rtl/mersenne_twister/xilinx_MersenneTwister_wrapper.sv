// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module xilinx_MersenneTwister_wrapper #(
    parameter int CLK_LED_COUNT_LENGTH = 26,
    parameter int unsigned LENGTH = 32
)(
	//Clock & Reset
    input  logic        clk_i,
    input  logic        rst_i,

    //Debug LED
    output logic        rst_led_o,   
    output logic        clk_led_o,   
	
	//Interfaccia MersenneTwister 
    input  logic        request_random_number_i,
    input  logic        request_reseed_i,
    input  logic [LENGTH-1:0] seed_i,
    output logic        ready_o,
    output logic        valid_o,
    output logic        busy_o,
    output logic [LENGTH-1:0] random_number_o
);


	//  Segnali interni
    wire clk_buf;   
    wire rst_n;     

    logic [CLK_LED_COUNT_LENGTH-1:0] clk_count;


	//Ricezione del clock: IBUF + BUFG
    IBUF clk_ibuf_i (
        .I (clk_i),
        .O (clk_buf)
    );

 	// Reset adaptation
    assign rst_n = ~rst_i;


	// debug LED
    assign rst_led_o = rst_n;
    assign clk_led_o = clk_count[CLK_LED_COUNT_LENGTH-1];

    always_ff @(posedge clk_buf or negedge rst_n) begin : heartbeat_counter
        if (!rst_n)
            clk_count <= '0;
        else
            clk_count <= clk_count + 1'b1;
    end


	// Instantiate the public MersenneTwister wrapper.
	// The low level core still works on 32-bit words; here the FPGA wrapper exposes
	// the classic 32-bit interface, so one core word is enough for each request.
    (* DONT_TOUCH = "yes", KEEP_HIERARCHY = "yes" *)
    MersenneTwister #(
        .LENGTH (LENGTH)
    ) mersennetwister_i (
        .clk_i                (clk_buf),
        .nRST                 (rst_n),
        .request_RandomNumber (request_random_number_i),
        .request_Reseed       (request_reseed_i),
        .seed                 (seed_i),
        .ready_o              (ready_o),
        .valid_o              (valid_o),
        .busy_o               (busy_o),
        .RandomNumber         (random_number_o)
    );

endmodule
