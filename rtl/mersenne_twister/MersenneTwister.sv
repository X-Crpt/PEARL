// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Simple wrapper around the 32-bit MersenneTwister_core.
//
// The core below is the MT19937-style block already used in this project, so it naturally produces
// 32 bits at a time. This wrapper only adapts the output length:
// - if L <= 32, it requests one word and keeps the least significant L bits;
// - if L > 32, it requests more words and concatenates them starting from the LSB side.
//
// Example with L = 96:
//   RandomNumber[31:0]   = first  core output
//   RandomNumber[63:32]  = second core output
//   RandomNumber[95:64]  = third  core output
//
// This is not a new mathematical version of Mersenne Twister. It is only a simple interface
// adapter that makes the 32-bit core easier to use inside other PRNG architectures.
// ==============================================================================================

module MersenneTwister #(
	parameter int unsigned LENGTH = 32
)(
	input	logic 			clk_i,
	input	logic			nRST,
	input	logic			request_RandomNumber,
	input	logic			request_Reseed,
	input	logic	[LENGTH-1:0] seed,
	output	logic			ready_o,
	output	logic			valid_o,
	output	logic			busy_o,
	output	logic	[LENGTH-1:0] RandomNumber
);

	localparam int unsigned CORE_WORD_BITS	= 32;
	localparam int unsigned WORDS_NEEDED	= (LENGTH + CORE_WORD_BITS - 1) / CORE_WORD_BITS;
	localparam int unsigned BUFFER_BITS		= WORDS_NEEDED * CORE_WORD_BITS;
	localparam int unsigned WORD_CNT_BITS	= (WORDS_NEEDED <= 1) ? 1 : $clog2(WORDS_NEEDED);
	localparam int unsigned SEED_COPY_BITS	= (LENGTH < CORE_WORD_BITS) ? LENGTH : CORE_WORD_BITS;

	typedef enum logic [2:0] {
		IDLE,
		RESEED_WAIT,
		START_WORD,
		WAIT_WORD,
		DONE
	} state_t;

	state_t state_reg;

	logic [WORD_CNT_BITS-1:0]	words_done;
	logic [BUFFER_BITS-1:0]		random_buffer;

	logic						core_request_RandomNumber;
	logic						core_request_Reseed;
	logic [CORE_WORD_BITS-1:0]	core_seed;
	logic						core_ready;
	logic						core_valid;
	logic						core_busy;
	logic [CORE_WORD_BITS-1:0]	core_random_number;

	always_comb begin
		core_seed = '0;
		core_seed[SEED_COPY_BITS-1:0] = seed[SEED_COPY_BITS-1:0];
	end

	always_comb begin
		core_request_RandomNumber	= 1'b0;
		core_request_Reseed			= 1'b0;

		case (state_reg)
			IDLE: begin
				if (request_Reseed && !request_RandomNumber && core_ready) begin
					core_request_Reseed = 1'b1;
				end
			end

			START_WORD: begin
				if (core_ready) begin
					core_request_RandomNumber = 1'b1;
				end
			end

			default: ;
		endcase
	end

	assign ready_o		= (state_reg == IDLE) && core_ready;
	assign valid_o		= (state_reg == DONE);
	assign busy_o		= (state_reg != IDLE) || core_busy;
	assign RandomNumber	= random_buffer[LENGTH-1:0];

	always_ff @(posedge clk_i) begin
		if (nRST == 1'b0) begin
			state_reg		<= IDLE;
			words_done		<= '0;
			random_buffer	<= '0;
		end else begin
			case (state_reg)
				IDLE: begin
					words_done <= '0;

					if (request_Reseed && !request_RandomNumber && core_ready) begin
						state_reg <= RESEED_WAIT;
					end else if (request_RandomNumber && core_ready) begin
						random_buffer	<= '0;
						state_reg		<= START_WORD;
					end
				end

				RESEED_WAIT: begin
					if (core_ready && !core_busy) begin
						state_reg <= IDLE;
					end
				end

				START_WORD: begin
					if (core_ready) begin
						state_reg <= WAIT_WORD;
					end
				end

				WAIT_WORD: begin
					if (core_valid) begin
						random_buffer[words_done*CORE_WORD_BITS +: CORE_WORD_BITS] <= core_random_number;

						if (words_done == WORD_CNT_BITS'(WORDS_NEEDED - 1)) begin
							state_reg <= DONE;
						end else begin
							words_done <= words_done + 1'b1;
							state_reg <= START_WORD;
						end
					end
				end

				DONE: begin
					state_reg <= IDLE;
				end

				default: begin
					state_reg <= IDLE;
				end
			endcase
		end
	end

	MersenneTwister_core core_i (
		.clk_i					(clk_i),
		.nRST					(nRST),
		.request_RandomNumber	(core_request_RandomNumber),
		.request_Reseed			(core_request_Reseed),
		.seed					(core_seed),
		.ready_o				(core_ready),
		.valid_o				(core_valid),
		.busy_o					(core_busy),
		.RandomNumber			(core_random_number)
	);

endmodule


// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// Original Mersenne Twister datapath used in the project.
//
// This block is kept as the low level core. With the default parameters it implements the 32-bit
// MT19937-style generator and produces one 32-bit word for each accepted random-number request.
// The external MersenneTwister wrapper above can call this core multiple times when a wider output
// vector is needed.
// ==============================================================================================

module MersenneTwister_core #(parameter
	// Default parameters follow the 32-bit MT19937 Mersenne Twister version.
	N	= 624,
	M	= 397,
	F	= 1812433253,
	L	= 32,
	B	= 32'h9D2C5680,
	C	= 32'hEFC60000,
	U	= 11,
	S	= 7,
	T	= 15,
	l	= 18,
	Up	= 32'h80000000,
	LL	= 32'h7FFFFFFF,
    A	= 32'h9908B0DF
)(
	input	logic 			clk_i,
	input	logic			nRST,
	input	logic			request_RandomNumber,
	input	logic			request_Reseed,
	input	logic	[L-1:0] seed,
	output	logic			ready_o,
	output	logic			valid_o,
	output	logic			busy_o,
	output	logic	[L-1:0] RandomNumber
);

	logic VGEN_EN,WV_EN,OUT_EN,AD_OR,REG_FILE_EN,MUXs_Feedback_EN;
	logic[$clog2(N)-1:0] AD_0,AD_1,AD_2,AD_0_Delayed;
	logic[L-1:0] dataVectorGenerator,REG_FILE_DATA_IN,x0,x1,xm,xOut;


	FSM_MODULE #(.N(N), .M(M)) fsm (clk_i,nRST,request_RandomNumber,request_Reseed,AD_0,AD_1,AD_2,VGEN_EN,WV_EN,OUT_EN,REG_FILE_EN,MUXs_Feedback_EN,valid_o,busy_o,ready_o);

	assign AD_OR = |AD_0;

	VectorGenerator #(.N(N),.L(L),.F(F)) V_Gen (clk_i,nRST,VGEN_EN,AD_OR,seed,AD_0,dataVectorGenerator);

	WordsGenerator #(.L(L),.U(Up),.LL(LL),.A(A)) W_Gen (x0,x1,xm,clk_i,nRST,WV_EN,xOut);

	OutputTamperer #(.L(L),.CONST1(B),.CONST2(C),.sh0(U),.sh1(S),.sh2(T),.sh3(l)) O_Temp (clk_i,nRST,OUT_EN,xOut,RandomNumber);

	MUX2 #(.LENGTH(L)) muxData (dataVectorGenerator,xOut,MUXs_Feedback_EN,REG_FILE_DATA_IN);

	//MUX2 #(.LENGTH($clog2(N))) muxAddress (AD_0,AD_0,MUXs_Feedback_EN,AD_0_REG_FILE);

	//REG #(.LENGTH($clog2(N))) regAdd (clk_i,MUXs_Feedback_EN,AD_0,AD_0_Delayed);

	REG_FILE #( .LENGTH(L) , .SIZE(N)) Xarray (clk_i,REG_FILE_EN,AD_0,AD_0,AD_1,AD_2,REG_FILE_DATA_IN,x0,x1,xm); 

endmodule

module REG_FILE 
#(parameter LENGTH = 16,
	parameter SIZE = 8
)(
	input logic clk_i, W_EN, 
	input logic[$clog2(SIZE)- 1:0] w_addr,r0_addr,r1_addr,r2_addr,
	input logic[LENGTH-1:0] w_DATA,
	output logic[LENGTH-1:0] r0_DATA,r1_DATA,r2_DATA
) ;

	logic[LENGTH-1:0] regs[0:SIZE-1];

	always_ff @(posedge clk_i)
		if (W_EN)
			regs[w_addr] <= w_DATA;


	assign r0_DATA = regs[r0_addr];
	assign r1_DATA = regs[r1_addr];
	assign r2_DATA = regs[r2_addr];

endmodule

module FSM_MODULE #(parameter
	N = 624,
	M = 397
)(
	input logic clk_i,nRST,RandomNumber_request,Reseed_request,
	output logic[$clog2(N)-1:0] AD_OUT_0,AD_OUT_1,AD_OUT_2,
	output logic V_GEN_OUT,W_V_EN,OUT_EN,REG_FILE_EN,MUXs_Feedback_EN,Valid,Busy,Ready
);


	logic CNT0_DONE,CNT1_DONE,CNT2_DONE,CNT0_E,CNT1_E,CNT2_E,CNT0_LD,CNT1_LD,CNT2_LD;

	logic[$clog2(N)-1:0] M_constant_signal,Signal0,Signal1;

	localparam W = $clog2(N); 

	assign Signal0 = W'(0);         
	assign Signal1 = W'(1); 
	assign M_constant_signal = W'(M);

	FSM StateMachine (clk_i,nRST,RandomNumber_request,Reseed_request,CNT0_DONE,CNT0_E,CNT1_E,CNT2_E,CNT0_LD,CNT1_LD,CNT2_LD,V_GEN_OUT,W_V_EN,OUT_EN,REG_FILE_EN,MUXs_Feedback_EN,Ready,Busy,Valid);


	COUNTER #(.MODULO(N), .W(W)) counter0 (clk_i,CNT0_E,nRST,CNT0_LD,Signal0,CNT0_DONE,AD_OUT_0);

	COUNTER #(.MODULO(N), .W(W)) counter1 (clk_i,CNT1_E,nRST,CNT1_LD,Signal1,CNT1_DONE,AD_OUT_1);

	COUNTER #(.MODULO(N), .W(W)) counter2 (clk_i,CNT2_E,nRST,CNT2_LD,M_constant_signal,CNT2_DONE,AD_OUT_2);

endmodule



module FSM (
	input logic clk_i,nRST,RandomNumber_request,Reseed_request,CNT0_DONE,
	output logic CNT_E_0,CNT_E_1,CNT_E_2,CNT_LD_0,CNT_LD_1,CNT_LD_2,V_GEN_EN,W_V_EN,OUT_EN,REG_FILE_EN,MUXs_Feedback_EN,Ready,Busy,Valid
);

	typedef enum {VECTOR_PREP,VECTOR_GEN, IDLE, WORD_GEN, WORD_STOP,WORD_DONE} state_t;
	state_t state_reg, state_next;



	always_ff @(posedge clk_i)

		if (nRST == 0)
			state_reg <= IDLE;
		else
			state_reg <= state_next;


	always_comb begin


		state_next = state_reg;
		CNT_E_0 = 1'b0;
		CNT_E_1 = 1'b0;
		CNT_E_2 = 1'b0;
		CNT_LD_0 = 1'b0;
		CNT_LD_1 = 1'b0;
		CNT_LD_2 = 1'b0;
		W_V_EN = 1'b0;
		OUT_EN = 1'b0;
	    V_GEN_EN = 1'b0;
		REG_FILE_EN = 1'b0;
	    MUXs_Feedback_EN = 1'b1;

		unique case (state_reg) 

	        VECTOR_PREP: begin //0

	        state_next = VECTOR_GEN;
	
	        CNT_LD_0 = 1'b1;
	        CNT_LD_1 = 1'b1;
	        CNT_LD_2 = 1'b1;
			Busy = 1'b1;
			Ready = 1'b0;
			Valid = 1'b0;

	        end

			VECTOR_GEN: begin //1
				CNT_E_0 = 1'b1; 
	            V_GEN_EN = 1'b1;
				CNT_LD_0 = 1'b0;
	            REG_FILE_EN = 1'b1;
				Busy = 1'b1;
				Ready = 1'b0;
				Valid = 1'b0;
	            MUXs_Feedback_EN = 1'b0;


				if (CNT0_DONE)
					state_next = IDLE;
			end

			IDLE:begin //2

	            Busy = 1'b0;
				Ready = 1'b1;
				Valid = 1'b0;
	
				if (Reseed_request & ~RandomNumber_request) begin
					state_next = VECTOR_PREP;
				end else if (RandomNumber_request) begin
	                state_next = WORD_GEN;
	            end
	            end


			WORD_GEN: begin //3

				state_next = WORD_STOP;

				W_V_EN = 1'b1;
				Busy = 1'b1;
				Ready = 1'b0;
				Valid = 1'b0;
				REG_FILE_EN = 1'b0;
				end

			WORD_STOP: begin //4

	       		CNT_E_0 = 1'b1;
				CNT_E_1 = 1'b1;
				CNT_E_2 = 1'b1;
				OUT_EN = 1'b1;
	            REG_FILE_EN = 1'b1;
				Busy = 1'b1;
				Ready = 1'b0;
				Valid = 1'b0;
	            MUXs_Feedback_EN = 1'b1;

	   			state_next = WORD_DONE;
	    	end

			WORD_DONE: begin

				Busy = 1'b0;
				Ready = 1'b0;
				Valid = 1'b1;

				state_next = IDLE;

			end

			default:begin
				state_next = IDLE;
			end

		endcase
	end
endmodule


module COUNTER
#( parameter MODULO = 500,
   parameter W = $clog2(MODULO)  // <-- larghezza esplicita come parameter
)
(
    input logic clk_i,EN,nRST,LOAD,
    input logic[W-1:0] P,
    output logic DONE,
    output logic[W-1:0] Q
);

	always_ff @(posedge clk_i)
		if (nRST == 0) begin
			Q <= 0;
		end else begin
			if (LOAD) begin
			    Q <= P;
		    end else if (EN & Q < MODULO-1) begin
				Q <= Q+1;
		    end else if (EN & Q >= MODULO-1) begin
	            Q <= 0;
	        end
	    end

	always_comb
		if (Q == (MODULO-1)) begin
			DONE = 1;
	        //Q = 0;
		end else begin
			DONE = 0;
		end


endmodule




module WordsGenerator #(parameter
    L = 32,
    U = 32'h80000000,
    LL = 32'h7FFFFFFF,
    A = 32'h9908B0DF
) (
	input logic[L-1:0] X0,X1,XM,
	input logic clk_i,nRST,EN,
	output logic[L-1:0] XOUT
) ;

	logic[L-1:0] AND0,AND1,OR1,XMout,Y,sY,MUXout,xor1,xorA;


	assign AND0 = X0 & U;
	assign AND1 = X1 & LL;
	assign OR1 = AND0 | AND1;
    
    REG #(.LENGTH(L)) RegY (clk_i,nRST,EN,OR1,Y);
	REG #(.LENGTH(L)) RegM (clk_i,nRST,EN,XM,XMout);

	RightShifter #(.AMOUNT(1)) rSHIFT(Y,sY);

    assign xor1 = XMout ^ sY;
    assign xorA = xor1 ^ A; 

    MUX2 #(.LENGTH(L)) mux (xor1,xorA,Y[0],XOUT);
    
endmodule


module VectorGenerator #(parameter
	N = 624,
	L = 32,
	F = 1812433253
)(
	input clk_i, nRST, EN, AD_OR, 
	input logic[L-1:0] seed,
	input logic[$clog2(N)-1:0] AD_w,
	output logic[L-1:0] dataOUT 
) ;

	
	logic[L-1:0] ADw32,Xreg,XregShifted,Xxor;
	logic[L:0] Xadd;
	logic[2*(L-1):0] Xmult;
	//logic ADmux;
	
	
	//assign ADmux = |AD_w;
	MUX2 #(.LENGTH(L)) muxWrite (seed,Xadd[L-1:0],AD_OR,dataOUT);
	
	RightShifter #(.AMOUNT(30)) xorShift (Xreg,XregShifted);
	assign Xxor = Xreg ^ XregShifted;
	
	Multiplier #(.LENGTH(L)) mult (F,Xxor,Xmult);
	
	assign ADw32 = {22'b0,AD_w};
	Adder #(.LENGTH(L)) add (ADw32,Xmult[L-1:0],Xadd);
	
	REG #(.LENGTH(L)) dataREG (clk_i, nRST, EN ,dataOUT,Xreg);
	
	//REG_FILE #( .LENGTH(L) , .SIZE(N)) Xarray (clk_i,EN,AD_w,AD_out0,AD_out1,AD_out2,dataOUT,X_out0,X_out1,X_out2); 

endmodule





module OutputTamperer #(parameter
    L = 32,
    CONST1 = 32'h9D2C5680,
    CONST2 = 32'hEFC60000,
    sh0 = 11,
    sh1 = 7,
    sh2 = 15,
    sh3 = 18   
) ( 
	input logic clk_i,nRST,EN,
	input logic[31:0] Y,
	output logic[31:0] RN
);


	logic[L-1:0] shift1,shift2,shift3,shift4,xor1,xor2,xor3,xor4;

	RightShifter #(.AMOUNT(sh0)) rs1 (Y,shift1);

	assign xor1 = Y ^ shift1;

	LeftShifter #(.AMOUNT(sh1)) ls1 (xor1,shift2);
	assign xor2 =  xor1 ^ (shift2 & CONST1);
	//assign and1 = CONST1 & shift1;


	LeftShifter #(.AMOUNT(sh2)) ls2 (xor2,shift3);
	assign xor3 =  xor2 ^ (shift3 & CONST2);
	//assign and2 = CONST2 & shift3;

	RightShifter #(.AMOUNT(sh3)) rs2 (xor3,shift4);
	assign xor4 = xor3 ^ shift4;

	REG #(.LENGTH(L)) reg1 (clk_i,nRST,EN,xor4,RN);

endmodule
	

