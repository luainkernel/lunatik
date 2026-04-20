--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local device = require("device")
local stat   = require("linux.stat")
local data   = require("data")
local runner = require("lunatik.runner")

local MAXVTS  <const> = 8
local MAXCOLS <const> = 200
local MAXROWS <const> = 60
local VTSIZE  <const> = MAXCOLS * MAXROWS
local BUFSIZE <const> = MAXVTS * VTSIZE

local script = "examples/vtmirror/notifier"
local grid   = data.new(BUFSIZE)
local driver = {name = "vtmirror", mode = stat.IRUGO | stat.IWUGO, watch = 1}

function driver:read(_, off)
	if off > 0 then return "" end
	local lines = {}
	local base = (self.watch - 1) * VTSIZE
	for y = 0, MAXROWS - 1 do
		local row = grid:getstring(base + y * MAXCOLS, MAXCOLS)
		row = row:gsub("%z", " "):gsub("%s+$", "")
		table.insert(lines, row)
	end
	while #lines > 0 and lines[#lines] == "" do
		lines[#lines] = nil
	end
	if #lines == 0 then return "" end
	return table.concat(lines, "\n") .. "\n"
end

function driver:write(buf)
	for cmd, value in string.gmatch(buf, "(%w+)=(%g+)") do
		if cmd == "watch" then
			local n = tonumber(value)
			if n and n >= 1 and n <= MAXVTS then
				self.watch = n
			end
		end
	end
end

device.new(driver)

local notifier = runner.run(script, "hardirq")
notifier:resume(grid)

driver.sentinel = setmetatable({}, {__gc = function()
	runner.stop(script)
end})

