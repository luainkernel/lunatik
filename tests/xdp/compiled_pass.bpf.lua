-- see test_xdp.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")
local packet = require("tests.xdp.packet")

return xdp.program(function(ctx)
	local data = ctx:packet()
	if packet.isping(data) then
		return action.PASS
	end
	return action.DROP
end, {name = "compiled_pass"})

