--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local device = require("device")

local driver = {name = "lunatik"}

function driver:read()
	local result = self.result
	self.result = nil
	return result
end

local function result(_, ...)
	return select("#", ...) > 0 and tostring(select(1, ...)) or ''
end

function driver:write(buf)
	local ok, err = load(buf)
	if ok then
		err = result(pcall(ok))
	end
	self.result = err
end

device.new(driver)

