--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local OUTPUT_DIR = "autogen"
local SCRIPT  = arg[0]
local KERNEL  = arg[1]
local INCLUDE = arg[2]
local MODULES = arg[3]

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
	io.stderr:write(string.format("%s: %s\n", SCRIPT, msg))
	os.exit(1)
end

if not KERNEL or not INCLUDE or not MODULES then
	exit("usage: lua5.4 " .. SCRIPT .. " <KERNEL> <INCLUDE> <MODULES>")
end

local CC = os.getenv("CC") or "cc"
local CPP = string.format("%s -E -dM -I%s", CC, INCLUDE)

local function preprocess(header_path)
	local cmd = string.format("%s %s/%s", CPP, INCLUDE, header_path)
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

local function resolve_value(value, constants, prefix, module_name, seen)
	if tonumber(value) then return value end

	if not constants[value] then return nil end

	seen = seen or {}
	-- recursion check: avoid cyclic defines
	if seen[value] then return nil end
	seen[value] = true

	if value:find("^" .. prefix) then
		local stripped = value:gsub("^" .. prefix, "")
		return string.format('%s["%s"]', module_name, stripped)
	end

	return resolve_value(constants[value], constants, prefix, module_name, seen)
end

local function write_constants(file, module, spec, constants, macro_names)
	for _, macro in ipairs(macro_names) do
		local field_name = macro:gsub("^" .. spec.prefix, "")
		local resolved_value = resolve_value(constants[macro], constants, spec.prefix, spec.module_name)
		if resolved_value then
			file:write(string.format('%s["%s"]\t= %s\n', spec.module_name, field_name, resolved_value))
		end
	end
end

local function write_module(dir, module, writer, ...)
	local filepath = string.format("%s/%s/%s.lua", OUTPUT_DIR, dir, module)
	local file <close>, err = io.open(filepath, "w")
	if not file then
		exit("cannot open " .. filepath .. ": " .. err)
	end
	file:write("-- auto-generated, do not edit\n")
	file:write("-- kernel: " .. KERNEL .. "\n\n")
	file:write("local " .. module .. " = {}\n\n")
	writer(file, module, ...)
	file:write("\nreturn " .. module .. "\n\n")
end

local function write_config(file, module)
	file:write(string.format('%s.kernel_version = "%s"\n', module, KERNEL))
	file:write(string.format('%s.modules = {\n\t"lunatik",\n', module))
	for m in MODULES:gmatch("%S+") do
		file:write(string.format('\t"lua%s",\n', m:lower()))
	end
	file:write('\t"lunatik_run"\n}\n')
end

for _, spec in ipairs(specs) do
	local cpp_output = preprocess(spec.header)
	local constants, macro_names = collect_constants(cpp_output, spec.prefix)
	write_module("linux", spec.module_name, write_constants, spec, constants, macro_names)
end

write_module("lunatik", "config", write_config)

