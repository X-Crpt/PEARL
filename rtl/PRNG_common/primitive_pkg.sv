`timescale 1ns/1ps

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Lorenzo Garbarino, Andrea Viola, Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------
// This package contains the common constants used to select cryptographic primitive cores inside
// higher-level generators.
//
// In this project, a primitive core is a stateless hardware block used as a deterministic
// n-bit -> n-bit transform by a PRNG architecture. AES and Keccak belong to different
// cryptographic families, but they can both be wrapped behind this kind of block interface.
//
// Notes:
// - Core identifiers are localparam int unsigned instead of enum values, because this style is
//   usually easier to handle with different simulation and synthesis tools.
// - These constants only select primitive cores compatible with this interface. A different
//   black-box interface should use a different selector.
// ==============================================================================================

package primitive_pkg;

	// Identifiers of the primitive core that can be selected by top-level modules.
	localparam int unsigned PRIMITIVE_CORE_KECCAK	= 0;
	localparam int unsigned PRIMITIVE_CORE_AES		= 1;

endpackage
