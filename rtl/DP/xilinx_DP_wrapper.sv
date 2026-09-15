// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module xilinx_DP_wrapper #(
	parameter int CLK_LED_COUNT_LENGTH = 26,
	parameter int unsigned LENGTH_STATE = 32,
	parameter int unsigned LENGTH_SEED = 16,
	parameter int unsigned EXTRACTOR_CORE = primitive_pkg::PRIMITIVE_CORE_KECCAK,
	parameter int unsigned PRG_CORE = primitive_pkg::PRIMITIVE_CORE_KECCAK
) (
	input  logic        clk_i,
	input  logic        rst_i,

	output logic        rst_led_o,
	output logic        clk_led_o,

	input  logic        request_reseed_i,
	input  logic        request_random_number_i,
	input  logic [LENGTH_SEED-1:0] seed_i,
	output logic        ready_o,
	output logic        valid_o,
	output logic        busy_o,
	output logic [LENGTH_SEED-1:0] random_number_o
);

	wire clk_buf;
	wire rst_n;

	logic [CLK_LED_COUNT_LENGTH-1:0] clk_count;

	IBUF clk_ibuf_i (
		.I(clk_i),
		.O(clk_buf)
	);

	assign rst_n = ~rst_i;

	assign rst_led_o = rst_n;
	assign clk_led_o = clk_count[CLK_LED_COUNT_LENGTH-1];

	always_ff @(posedge clk_buf or negedge rst_n) begin : heartbeat_counter
		if (!rst_n) begin
			clk_count <= '0;
		end else begin
			clk_count <= clk_count + 1'b1;
		end
	end

	(* DONT_TOUCH = "yes", KEEP_HIERARCHY = "yes" *)
	DP #(
		.LENGTH_STATE	(LENGTH_STATE),
		.LENGTH_SEED	(LENGTH_SEED),
		.EXTRACTOR_CORE	(EXTRACTOR_CORE),
		.PRG_CORE		(PRG_CORE)
	) dp_i (
		.clk_i                (clk_buf),
		.nRST                 (rst_n),
		.request_Reseed       (request_reseed_i),
		.request_RandomNumber (request_random_number_i),
		.seed                 (seed_i),
		.ready_o              (ready_o),
		.valid_o              (valid_o),
		.busy_o               (busy_o),
		.RandomNumber         (random_number_o)
	);

endmodule
