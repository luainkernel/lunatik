--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local device = require("device")

local driver = {name = "lunatik"}

function driver:read(len, off, file)
	local result = file.result or ""
	file.result = result:sub(len + 1)
	return result:sub(1, len)
end

local function result(ok, ...)
	local n = select('#', ...)
	local t = {}
	for i = 1, n do
		t[i] = tostring(select(i, ...))
	end
	return tostring(ok) .. '\t' .. table.concat(t, '\t')
end

function driver:write(buf, off, file)
	local chunk, err = load(buf)
	file.result = chunk and result(pcall(chunk)) or result(false, err)
end

device.new(driver)

