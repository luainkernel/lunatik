--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local specs = {
	{
		header = "uapi/linux/if_ether.h",
		prefix = "ETH_P_",
		module_name = "eth",
	},
	{
		header = "uapi/linux/stat.h",
		prefix = "S_",
		module_name = "stat",
	},
	{
		header = "uapi/linux/signal.h",
		prefix = "SIG",
		module_name = "signal",
	}
}

local function exit(msg)
	io.stderr:write("genconstants.lua: " .. msg .. "\n")
	os.exit(1)
end

local KERNEL = arg[1]
local INCLUDE_PATH = arg[2]
local OUTPUT_DIR = arg[3]

if not KERNEL or not INCLUDE_PATH or not OUTPUT_DIR then
	exit("usage: lua genconstants.lua <KERNEL> <INCLUDE_PATH> <OUTPUT_DIR>")
end

local CC = os.getenv("CC") or "cc"
local CPP_CMD = string.format("%s -E -dM -I%s", CC, INCLUDE_PATH)

local function preprocess(header_path)
	local cmd = string.format("%s %s/%s", CPP_CMD, INCLUDE_PATH, header_path)
	local pipe <close> = io.popen(cmd)
	if not pipe then
		exit("failed to run preprocessor on " .. header_path)
	end
	return pipe:read("*a")
end

local function collect_constants(cpp_output, prefix)
	local constants = {}
	local macro_names = {}

	for macro, literal in cpp_output:gmatch("#define%s+(" .. prefix .. "%w+)%s+(%S+)") do
		constants[macro] = literal
		table.insert(macro_names, macro)
	end

	table.sort(macro_names)
	return constants, macro_names
end

local function resolve_aliases(constants, macro_names, prefix, module_name)
	for _, macro in ipairs(macro_names) do
		local definition = constants[macro]
		local stripped_name = definition:gsub("^" .. prefix, "")
		if stripped_name ~= definition and constants[prefix .. stripped_name] then
			constants[macro] = module_name .. '["' .. stripped_name .. '"]'
		end
	end
end

local function write_module(spec, constants, macro_names)
	local filepath = string.format("%s/%s.lua", OUTPUT_DIR, spec.module_name)
	local file <close>, err = io.open(filepath, "w")
	if not file then
		exit("cannot open " .. filepath .. ": " .. err)
	end
	file:write("-- auto-generated, do not edit\n")
	file:write("-- kernel: " .. KERNEL .. "\n\n")
	file:write("local " .. spec.module_name .. " = {}\n\n")
	for _, macro in ipairs(macro_names) do
		local field_name = macro:gsub("^" .. spec.prefix, "")
		file:write(string.format('%s["%s"] = %s\n', spec.module_name, field_name, constants[macro]))
	end
	file:write("\nreturn " .. spec.module_name .. "\n")
end

for _, spec in ipairs(specs) do
	local cpp_output = preprocess(spec.header)
	local constants, macro_names = collect_constants(cpp_output, spec.prefix)
	resolve_aliases(constants, macro_names, spec.prefix, spec.module_name)
	write_module(spec, constants, macro_names)
end

