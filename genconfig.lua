-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only

local function exit(msg)
    io.stderr:write("genconfig.lua: " .. msg .. "\n")
    os.exit(1)
end

local KERNEL_RELEASE = arg[1]
local OUTPUT_DIR = arg[2]
local CONFIGS = arg[3]

if not KERNEL_RELEASE or not OUTPUT_DIR or not CONFIGS then
	exit("usage: lua genconfig.lua <KERNEL_RELEASE> <OUTPUT_DIR> <CONFIGS>")
end

local ignore_list = {
    ["INSTALL_EXAMPLES"] = true,
    ["INSTALL_TESTS"] = true,
    ["RUNTIME"] = true
}

local modules = {}

for token in CONFIGS:gmatch("%S+") do
	local key = token:match("(CONFIG_[%w_]+)=[my]")
	if key then
		local name
		if key == "CONFIG_LUNATIK" then
			name = "lunatik"
		elseif key == "CONFIG_LUNATIK_RUN" then
			name = "lunatik_run"
		else
			local suffix = key:match("CONFIG_LUNATIK_(.+)")
			if suffix then
				if not ignore_list[suffix] then
					name = "lua" .. suffix:lower()
				end
			end
		end
		if name then
			table.insert(modules, name)
		end
	end
end

local filepath = OUTPUT_DIR .. "/config.lua"
local file <close>, err = io.open(filepath, "w")
if not file then
    exit("cannot open " .. filepath .. ": " .. err)
end

file:write("-- auto-generated, do not edit\n")
file:write("local config = {}\n\n")
file:write(string.format('config.kernel_release = "%s"\n', KERNEL_RELEASE))
file:write("config.modules = {\n")
for _, mod in ipairs(modules) do
    file:write(string.format('\t"%s",\n', mod))
end
file:write("}\n\n")
file:write("return config\n")