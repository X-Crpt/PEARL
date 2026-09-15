// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module xilinx_ctr_drbg_wrapper #(
	parameter int CLK_LED_COUNT_LENGTH = 26,
	parameter int unsigned OUTLEN = 128,
	parameter int unsigned KEYLEN = 128,
	parameter int unsigned REQ_NUM_BITS = 128,
	parameter int unsigned RESEED_CTR_BITS = 8,
	parameter int unsigned ENCRYPTION_CORE = primitive_pkg::PRIMITIVE_CORE_AES
) (
	input  logic         clk_i,
	input  logic         rst_i,

	output logic         rst_led_o,
	output logic         clk_led_o,

	input  logic         request_rn_i,
	input  logic [KEYLEN+OUTLEN-1:0] entropy_i,
	output logic         ready_o,
	output logic         busy_o,
	output logic         valid_o,
	output logic [REQ_NUM_BITS-1:0] output_rn_o
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
	ctr_drbg #(
		.OUTLEN				(OUTLEN),
		.KEYLEN				(KEYLEN),
		.REQ_NUM_BITS		(REQ_NUM_BITS),
		.RESEED_CTR_BITS	(RESEED_CTR_BITS),
		.ENCRYPTION_CORE	(ENCRYPTION_CORE)
	) ctr_drbg_i (
		.clk_i        (clk_buf),
		.rst_n_i      (rst_n),
		.request_RN_i (request_rn_i),
		.entropy_i    (entropy_i),
		.ready_o      (ready_o),
		.busy_o       (busy_o),
		.valid_o      (valid_o),
		.output_RN_o  (output_rn_o)
	);

endmodule
