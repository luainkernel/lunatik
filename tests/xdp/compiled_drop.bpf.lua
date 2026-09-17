-- see test_xdp.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")
local packet = require("tests.xdp.packet")

return xdp.program(function(ctx)
	local data = ctx:packet()
	if packet.isping(data) then
		return action.DROP
	end
	return action.PASS
end, {name = "compiled_drop"})

