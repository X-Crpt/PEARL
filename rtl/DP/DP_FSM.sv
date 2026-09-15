// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

module DP_FSM #(parameter
	start_odd = 1		// To be set to 1 if the first constant to be used is B
) (
    input	logic	clk_i,
	input	logic	nRST,
	input	logic	request_Reseed,
	input	logic	request_RandomNumber,
	input	logic	PRNG_ready,
	input	logic	PRNG_valid,
	input	logic	PRNG_busy,
	input	logic	Ext_done,
	
	// Control Signals for controlled by this Control Unit
	output	logic	RegAEn, 			//
	output	logic	RegBEn, 			//
	output	logic	RegSEEDEn, 			//
	output	logic	Mux_in_sel, 		// Input MUXes 
	output	logic	mux_ext_sel, 		//
	output	logic	Ext_start,			//
	output	logic	PRNG_request_RandomNumber,	//
	output	logic	PRNG_request_Reseed,		//

	// Status signal exposed by the Control Unit
	output	logic	ready_o,				// Can the DP accept a new request?
	output	logic	valid_o,				// Is the data at the DP's output valid? 
	output	logic	busy_o				// Is the DP unit busy (is it processing something?)
);

	// Define the states for the Main DP's FSM 
	typedef enum {
		IDLE, 
		LOAD_SEED,
		EXT_START, 
		UPDATE_SEED,
		PRNG_START, 
		PRNG_WAIT, 
		WRITE_BACK
	} state_t;
	state_t	state_reg;
	state_t	state_next;

	// Internal states of the Control Unit
	logic	isSeeded;
	logic	isInitialized;
	logic	isOdd;

	// Internal signals for the CU
	logic	isSeeded_next;
	logic	isInitialized_next;
	logic	isOdd_next;	

	// Update to the next state only at the active clock cycle edge
	always_ff @(posedge clk_i) begin
		if (nRST == 0) begin 
			state_reg		<= IDLE;
			isSeeded		<= 1'b0; 
			isInitialized	<= 1'b0;
			isOdd			<= start_odd; 
		end else begin 
			state_reg		<= state_next;
			isSeeded		<= isSeeded_next;
			isInitialized	<= isInitialized_next;
			isOdd			<= isOdd_next;
		end 
	end 

	// Combinatorially define the state of the Output Control signals of the CU 
	// Combinatorially define the next state
	always_comb begin

		// Define the default values of FSM's signals
		state_next			= state_reg;
		isSeeded_next		= isSeeded;
		isInitialized_next	= isInitialized;
		isOdd_next			= isOdd;
		ready_o				= (state_reg == IDLE);
		valid_o				= 1'b0;
		busy_o				= (state_reg != IDLE);
		RegAEn				= 1'b0;
		RegBEn				= 1'b0;
		RegSEEDEn			= 1'b0;
		Mux_in_sel			= 1'b0;
		mux_ext_sel			= isOdd;
		Ext_start			= 1'b0;
		PRNG_request_RandomNumber	= 1'b0;
		PRNG_request_Reseed			= 1'b0;
		

		unique case (state_reg)

			IDLE: begin
				// Define signals that are different from the Deafult in this state
				busy_o = 1'b0;

				// Define the next state
				if (request_Reseed) begin
					state_next = LOAD_SEED;
				end else if (request_RandomNumber && isSeeded) begin
					state_next = EXT_START;
				end else begin
					state_next = IDLE;
				end
			end
			

			LOAD_SEED: begin
				// Load the new seed. On the first reseed only, also load A/B from
				// the init-side inputs selected by Mux_in_sel = 0.
				RegSEEDEn = 1'b1;
				Mux_in_sel = 1'b0;

				if (!isInitialized) begin
					RegAEn = 1'b1;
					RegBEn = 1'b1;
					isInitialized_next = 1'b1;
				end

				isSeeded_next = 1'b1;
				isOdd_next = start_odd;
				state_next = IDLE;
			end
			
			EXT_START: begin
				// Define signals that are different from the Deafult in this state
				Mux_in_sel = 1'b1;
				Ext_start = 1'b1;
				
				// Define the next state
				if (Ext_done) begin 
					state_next = UPDATE_SEED;
				end
			end

			UPDATE_SEED: begin
				// Store the new DP seed extracted from Keccak output.
				RegSEEDEn = 1'b1;
				Mux_in_sel = 1'b1;

				state_next = PRNG_START;
			end 
							
			PRNG_START: begin
				// Define signals that are different from the Deafult in this state
				if (PRNG_ready) begin
					PRNG_request_RandomNumber = 1'b1;
					state_next = PRNG_WAIT;
				end
			end 

			PRNG_WAIT: begin 
				// Define the next state
				if (PRNG_valid) begin 
					state_next = WRITE_BACK;
				end
			end
				
			WRITE_BACK: begin 
				// Define signals that are different from the Deafult in this state
				if (isOdd) begin
					RegBEn = 1'b1;
				end else begin 
					RegAEn = 1'b1;
				end
				Mux_in_sel = 1'b1;
				valid_o = 1'b1;
				isOdd_next = ~isOdd;

				// Define the next state
				state_next = IDLE;
			end
		
		endcase
	end 

	// Update the internal states of the Control Unit

endmodule


	

	



	



		
		





 
