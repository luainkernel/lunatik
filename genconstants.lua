--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local MODULE_PATH = "./lib/linux"

local specs = {
	{
		header = "linux/if_ether.h",
		prefix = "ETH_P_",
		module_name = "eth",
	},
	{
		header = "linux/stat.h",
		prefix = "S_",
		module_name = "stat",
	},
	{
		header = "linux/signal.h",
		prefix = "SIG",
		module_name = "signal",
	}
}

local function exit(msg)
	io.stderr:write("genconstants.lua: " .. msg .. "\n")
	os.exit(1)
end

local function preprocess(header)
	local cc = os.getenv("CC")
	local cmd = string.format("echo '#include <%s>' | %s -E -dM -", header, cc)

	local p = io.popen(cmd)

	if not p then
		exit("failed to run cpp on " .. header)
	end

	local out = p:read("*a")
	p:close()
	return out
end

local function extract_defines(text, prefix)
	local defs = {}
	for name, value in text:gmatch("#define%s+(" .. prefix .. "%w+)%s+(%S+)") do
		defs[name] = value
	end
	return defs
end

local function main()
	for _, spec in ipairs(specs) do
		local text = preprocess(spec.header)
		local defs = extract_defines(text, spec.prefix)

		local filename = string.format("%s/%s.lua", MODULE_PATH, spec.module_name)

		local out, err = io.open(filename, "w")
		if not out then
			exit("cannot open " .. filename .. ": " .. err)
		end

		out:write("-- auto-generated, do not edit\n")
		out:write("-- kernel: " .. spec.header .. "\n\n")
		out:write("local " .. spec.module_name .. " = {}\n\n")

		local keys = {}
		for k in pairs(defs) do
			table.insert(keys, k)
		end

		table.sort(keys)

		for _, k in ipairs(keys) do
			local lua_name = k:gsub("^" .. spec.prefix, "")
			out:write(string.format(
				"%s[\"%s\"] = %s\n",
				spec.module_name,
				lua_name,
				defs[k]
			))
		end

		out:write("\nreturn " .. spec.module_name .. "\n\n")
		out:close()
	end
end

main()

