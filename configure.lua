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
		-- composites from linux/stat.h (kernel-internal OR'd flags)
		supplement = "linux/stat.h",
	},
	{
		header = "uapi/linux/signal.h",
		prefix = "SIG",
		module_name = "signal",
	},
	{
		-- kernel-internal header, extracted via grep (not preprocessor)
		header = "linux/sched.h",
		prefix = "TASK_",
		module_name = "task",
		internal = true,
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

-- Extract #define lines directly from a kernel-internal header file (no preprocessing).
-- Handles simple values (hex/decimal) and single-line OR expressions like (A | B).
local function grep_constants(header_path, prefix)
	local filepath = string.format("%s/%s", INCLUDE, header_path)
	local file <close> = io.open(filepath, "r")
	if not file then
		exit("cannot open " .. filepath)
	end

	local constants = {}
	local macro_names = {}

	for line in file:lines() do
		local macro, value = line:match("^#define%s+(" .. prefix .. "%w+)%s+(.+)$")
		if macro and value then
			value = value:gsub("%s+$", "")  -- trim trailing whitespace
			-- skip multi-line macros (ending with backslash) and function-like macros
			if not value:find("\\$") and not macro:find("%(") then
				constants[macro] = value
				table.insert(macro_names, macro)
			end
		end
	end

	table.sort(macro_names)
	return constants, macro_names
end

-- Parse a C-style numeric literal: 0x prefix for hex, leading 0 for octal, else decimal.
local function parse_c_number(s)
	if not s then return nil end
	if s:find("^0[xX]") then
		return tonumber(s)  -- Lua handles 0x natively
	elseif s:find("^0%d") then
		return tonumber(s, 8)  -- octal
	else
		return tonumber(s)
	end
end

-- Resolve a value to a numeric result. Handles:
-- 1. Numeric literals (decimal, hex, octal)
-- 2. References to other macros (resolved recursively)
-- 3. OR expressions like (MACRO_A | MACRO_B)
local function resolve_numeric(value, constants, seen)
	if not value then return nil end

	-- numeric literal
	local n = parse_c_number(value)
	if n then return n end

	seen = seen or {}
	if seen[value] then return nil end
	seen[value] = true

	-- reference to another macro
	if constants[value] then
		return resolve_numeric(constants[value], constants, seen)
	end

	-- OR expression: (A|B|C) or (A | B | C)
	local inner = value:match("^%((.+)%)$")
	if inner then
		local result = 0
		for term in inner:gmatch("[^|]+") do
			term = term:match("^%s*(.-)%s*$")  -- trim
			local n = resolve_numeric(term, constants, seen)
			if not n then return nil end
			result = result | n
		end
		return result
	end

	return nil
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

-- Write constants extracted via grep (kernel-internal headers).
-- Resolves all values to numeric and emits them.
local function write_grep_constants(file, module, spec, constants, macro_names)
	for _, macro in ipairs(macro_names) do
		local field_name = macro:gsub("^" .. spec.prefix, "")
		local num = resolve_numeric(constants[macro], constants)
		if num then
			file:write(string.format('%s["%s"]\t= 0x%08x\n', module, field_name, num))
		end
	end
end

-- Read supplementary defines from a kernel-internal header and merge into
-- existing constants (for composites like S_IRWXUGO defined in linux/stat.h).
local function supplement_constants(header_path, prefix, constants, macro_names)
	local filepath = string.format("%s/%s", INCLUDE, header_path)
	local file <close> = io.open(filepath, "r")
	if not file then
		exit("cannot open " .. filepath)
	end

	for line in file:lines() do
		local macro, value = line:match("^#define%s+(" .. prefix .. "%w+)%s+(.+)$")
		if macro and value and not constants[macro] then
			value = value:gsub("%s+$", "")
			if not value:find("\\$") then
				-- Resolve OR expression to numeric using already-known constants
				local inner = value:match("^%((.+)%)$")
				if inner then
					local result = 0
					local ok = true
					for term in inner:gmatch("[^|]+") do
						term = term:match("^%s*(.-)%s*$")
						local n = resolve_numeric(term, constants)
						if not n then ok = false; break end
						result = result | n
					end
					if ok then
						constants[macro] = tostring(result)
						table.insert(macro_names, macro)
					end
				end
			end
		end
	end

	table.sort(macro_names)
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
	if spec.internal then
		-- kernel-internal header: extract via grep, resolve to numeric values
		local constants, macro_names = grep_constants(spec.header, spec.prefix)
		write_module("linux", spec.module_name, write_grep_constants, spec, constants, macro_names)
	else
		-- uapi header: use C preprocessor
		local cpp_output = preprocess(spec.header)
		local constants, macro_names = collect_constants(cpp_output, spec.prefix)
		-- merge supplementary constants from kernel-internal header if specified
		if spec.supplement then
			supplement_constants(spec.supplement, spec.prefix, constants, macro_names)
		end
		write_module("linux", spec.module_name, write_constants, spec, constants, macro_names)
	end
end

write_module("lunatik", "config", write_config)
