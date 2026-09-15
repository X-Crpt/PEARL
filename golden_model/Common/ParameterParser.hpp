#pragma once

// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "bytesNumber.hpp"
#include <cstddef>
#include <cstdint>
#include <initializer_list>
#include <string>
#include <vector>

using namespace std;

typedef struct {
	string name;
	string value;
} ParameterOverride;

class ParameterParser {
	public:
		ParameterParser(int argc, char* argv[], int first_param_arg);

		bool has			(const string& name) const;
		bool get_value		(const string& name, string& value) const;

		string		get_string		(const string& name, const string& default_value) const;
		int32_t		get_int32		(const string& name, int32_t default_value) const;
		bool		get_bool		(const string& name, bool default_value) const;
		bytesNumber	get_bytes		(const string& name, size_t expected_bytes, const string& default_hex) const;

	private:
		vector<ParameterOverride> parameter_overrides;

		static int32_t		parse_int32					(const string& value);
		static bool			parse_bool					(const string& value);
		static bytesNumber	parse_bytes					(const string& value, size_t expected_bytes);
		static string		normalize_sv_hex_literal	(string value);
};
