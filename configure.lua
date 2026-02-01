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
	io.stderr:write("gendefines.lua: " .. msg .. "\n")
	os.exit(1)
end

local KERNEL = arg[1]
local INCLUDE_PATH = arg[2]
local OUTPUT_DIR = arg[3]
local CONFIG_FLAGS = arg[4]

if not KERNEL or not INCLUDE_PATH or not OUTPUT_DIR or not CONFIG_FLAGS then
	exit("usage: lua gendefines.lua <KERNEL> <INCLUDE_PATH> <OUTPUT_DIR> <CONFIG_FLAGS>")
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

local function resolve_value(value, constants, prefix, module_name, seen)
	if tonumber(value) then
		return value
	end

	if not constants[value] then
		return nil
	end

	seen = seen or {}
	-- recursion check: avoid cyclic defines
	if seen[value] then
		return nil
	end
    seen[value] = true

	if value:find("^" .. prefix) then
        local stripped = value:gsub("^" .. prefix, "")
        return string.format('%s["%s"]', module_name, stripped)
    end

    return resolve_value(constants[value], constants, prefix, module_name, seen)
end

local function write_module(spec, constants, macro_names, output_dir)
	local filepath = string.format("%s/linux/%s.lua", output_dir, spec.module_name)
	local file <close>, err = io.open(filepath, "w")
	if not file then
		exit("cannot open " .. filepath .. ": " .. err)
	end
	file:write("-- auto-generated, do not edit\n")
	file:write("-- kernel: " .. KERNEL .. "\n\n")
	file:write("local " .. spec.module_name .. " = {}\n\n")
	for _, macro in ipairs(macro_names) do
		local field_name = macro:gsub("^" .. spec.prefix, "")
        local resolved_value = resolve_value(constants[macro], constants, spec.prefix, spec.module_name)
        if resolved_value then
            file:write(string.format('%s["%s"] = %s\n', spec.module_name, field_name, resolved_value))
        end
	end
	file:write("\nreturn " .. spec.module_name .. "\n")
end


local function generate_build_config(kernel_release, output_dir, configs)
	local module_map = {
		["CONFIG_LUNATIK"] = "lunatik",
		["CONFIG_LUNATIK_RUN"] = "lunatik_run"
	}

	local modules = {}

	for token in configs:gmatch("%S+") do
		local config_option = token:match("(CONFIG_[%w_]+)=[my]")
		if config_option then
			local name = module_map[config_option]
			if not name then
				local suffix = config_option:match("CONFIG_LUNATIK_(.+)")
				if suffix then
					name = "lua" .. suffix:lower()
				end
			end

			if name then
				table.insert(modules, name)
			end
		end
	end

	local filepath = output_dir .. "/lunatik/config.lua"
	local file <close>, err = io.open(filepath, "w")
	if not file then
		exit("cannot open " .. filepath .. ": " .. err)
	end

	file:write("-- auto-generated, do not edit\n")
	file:write("local config = {}\n\n")
	file:write(string.format('config.kernel_release = "%s"\n', kernel_release))
	file:write("config.modules = {\n")
	for _, mod in ipairs(modules) do
		file:write(string.format('\t"%s",\n', mod))
	end
	file:write("}\n\n")
	file:write("return config\n")
end

for _, spec in ipairs(specs) do
	local cpp_output = preprocess(spec.header)
	local constants, macro_names = collect_constants(cpp_output, spec.prefix)
	write_module(spec, constants, macro_names, OUTPUT_DIR)
end

generate_build_config(KERNEL, OUTPUT_DIR, CONFIG_FLAGS)

