// ==============================================================================================
// Project: PEARL -- PRNG Evaluation for Area, Randomness, and Leakage
// Authors: Valeria Piscopo, Alessandra Dolmeta (EDGE Group, VLSI Lab, Dept. of Electronics and Telecommunications, Politecnico di Torino);
//          Behnam Farnaghinejad (Dept. of Control and Computer Engineering, Politecnico di Torino)
// ----------------------------------------------------------------------------------------------

#include "ParameterParser.hpp"
#include <limits>
#include <stdexcept>

ParameterParser::ParameterParser(int argc, char* argv[], int first_param_arg) {
	for (int arg_idx = first_param_arg; arg_idx < argc; arg_idx++) {
		string raw_arg = argv[arg_idx];
		if (raw_arg.empty()) {
			continue;
		}
		if (raw_arg[0] == '+') {
			raw_arg.erase(0, 1);
		}

		size_t equal_pos = raw_arg.find('=');
		if ((equal_pos == string::npos) || (equal_pos == 0) || (equal_pos == (raw_arg.size() - 1))) {
			throw invalid_argument("ERROR: Parameter override must use +NAME=VALUE format: " + string(argv[arg_idx]));
		}

		ParameterOverride parameter_override;
		parameter_override.name = raw_arg.substr(0, equal_pos);
		parameter_override.value = raw_arg.substr(equal_pos + 1);
		parameter_overrides.push_back(parameter_override);
	}
}

bool ParameterParser::has(const string& name) const {
	string value;
	return get_value(name, value);
}

bool ParameterParser::get_value(const string& name, string& value) const {
	for (const ParameterOverride& parameter_override : parameter_overrides) {
		if (parameter_override.name == name) {
			value = parameter_override.value;
			return true;
		}
	}
	return false;
}

string ParameterParser::get_string(const string& name, const string& default_value) const {
	string value;
	if (get_value(name, value)) {
		return value;
	}
	return default_value;
}

int32_t ParameterParser::get_int32(const string& name, int32_t default_value) const {
	string value;
	if (get_value(name, value)) {
		return parse_int32(value);
	}
	return default_value;
}

bool ParameterParser::get_bool(const string& name, bool default_value) const {
	string value;
	if (get_value(name, value)) {
		return parse_bool(value);
	}
	return default_value;
}

bytesNumber ParameterParser::get_bytes(const string& name, size_t expected_bytes, const string& default_hex) const {
	string value;
	if (get_value(name, value)) {
		return parse_bytes(value, expected_bytes);
	}
	return parse_bytes(default_hex, expected_bytes);
}

int32_t ParameterParser::parse_int32(const string& value) {
	size_t parsed_chars = 0;
	long long parsed_value = stoll(value, &parsed_chars, 0);
	if (parsed_chars != value.size()) {
		throw invalid_argument("ERROR: Invalid int32 parameter value: " + value);
	}
	if ((parsed_value < numeric_limits<int32_t>::min()) || (parsed_value > numeric_limits<int32_t>::max())) {
		throw invalid_argument("ERROR: int32 parameter value out of range: " + value);
	}
	return static_cast<int32_t>(parsed_value);
}

bool ParameterParser::parse_bool(const string& value) {
	if ((value == "1") || (value == "true") || (value == "TRUE") || (value == "True")) {
		return true;
	}
	if ((value == "0") || (value == "false") || (value == "FALSE") || (value == "False")) {
		return false;
	}
	throw invalid_argument("ERROR: Invalid bool parameter value: " + value);
}

bytesNumber ParameterParser::parse_bytes(const string& value, size_t expected_bytes) {
	bytesNumber parsed_value;
	parsed_value.fromHexString(normalize_sv_hex_literal(value));
	parsed_value.setSize(expected_bytes);
	return parsed_value;
}

string ParameterParser::normalize_sv_hex_literal(string value) {
	size_t quote_pos = value.find('\'');
	if (quote_pos != string::npos) {
		if ((quote_pos + 1) >= value.size()) {
			throw invalid_argument("ERROR: Invalid SystemVerilog literal: " + value);
		}

		char base = value[quote_pos + 1];
		if ((base != 'h') && (base != 'H')) {
			throw invalid_argument("ERROR: Only hexadecimal SystemVerilog literals are supported: " + value);
		}
		value = value.substr(quote_pos + 2);
	}

	if ((value.size() >= 2) && (value[0] == '0') && ((value[1] == 'x') || (value[1] == 'X'))) {
		value = value.substr(2);
	}

	return value;
}
