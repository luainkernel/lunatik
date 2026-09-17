-- see test_tc.sh
local tc     = require("bpf.tc")
local action = require("linux.tc")
local packet = require("tests.tc.packet")

return tc.program(function(skb)
	local data = skb:packet()
	if packet.isping(data) then
		return action.ACT_OK
	end
	return action.ACT_SHOT
end, {egress = true, name = "compiled_pass"})

