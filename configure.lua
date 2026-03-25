--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local OUTPUT_DIR = "autogen"
local SCRIPT  = arg[0]
local KERNEL  = arg[1]
local BUILD   = arg[2]
local MODULES = arg[3]
local ARCH    = os.getenv("ARCH")

local specs = {
	{
		header = "uapi/linux/if_ether.h",
		prefix = "ETH_P_",
		module_name = "eth",
	},
	{
		header = "linux/stat.h",
		prefix = "S_",
		module_name = "stat",
	},
	{
		header = "uapi/linux/signal.h",
		prefix = "SIG",
		module_name = "signal",
	},
	{
		header = "linux/sched.h",
		prefix = "TASK_",
		module_name = "task",
	}
}

local function exit(msg)
	io.stderr:write(string.format("%s: %s\n", SCRIPT, msg))
	os.exit(1)
end

if not KERNEL or not BUILD or not MODULES or not ARCH then
	exit("usage: ARCH=<ARCH> lua5.4 " .. SCRIPT .. " <KERNEL> <BUILD> <MODULES>")
end

local CC = os.getenv("CC") or "cc"
local INCLUDE = BUILD .. "/include"
local CPP = string.format("%s -E -dM -I%s -I%s/include/generated -I%s/arch/%s/include -I%s/arch/%s/include/generated -include linux/kconfig.h",
	CC, INCLUDE, BUILD, BUILD, ARCH, BUILD, ARCH)

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

	for line in cpp_output:gmatch("[^\n]+") do
		local macro, value = line:match("#define%s+(" .. prefix .. "[%u%d_]+)%s+(.+)%s*$")
		if macro and not line:match("#define%s+" .. prefix .. "%w+%(") then
			constants[macro] = value
			table.insert(macro_names, macro)
		end
	end

	table.sort(macro_names)
	return constants, macro_names
end

local function resolve_value(value, prefix, constants, seen)
	seen = seen or {}
	if seen[value] then return nil end

	if tonumber(value) then return tonumber(value) end
	local clean = value:match("^%((.+)%)$") or value

	-- OR expression: (A | B | ...)
    if clean:find("|") then
        local result = 0
        for token in clean:gmatch("[^%s|]+") do
            local resolved = resolve_value(token, prefix, constants, seen)
            if not resolved then return nil end
            result = result | resolved
        end
        return result
    end

	-- macro reference
	if not constants[value] then return nil end

	seen[value] = true
	local res = resolve_value(constants[value], prefix, constants, seen)
	seen[value] = nil
	return res
end

local function write_constants(file, module, spec, constants, macro_names)
	for _, macro in ipairs(macro_names) do
		local field_name = macro:gsub("^" .. spec.prefix, "")
		local resolved_value = resolve_value(constants[macro], spec.prefix, constants)
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

