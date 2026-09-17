-- see load.sh
local map    = require("bpf.map")
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")

local ENTRIES <const> = 4
local HEADER  <const> = 14 -- an ethernet header, the shortest packet worth counting
local SEEN    <const> = 0

local counts = map.array("counts", {key = "I4", value = "I8", entries = ENTRIES})

return xdp.program(function(ctx)
	local packet = ctx:packet()
	if #packet < HEADER then
		return action.DROP
	end
	counts[SEEN] = #packet
	return action.PASS
end, {name = "loader"})

