-- see pass.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")

xdp.program(function(ctx)
	return action.PASS
end, {name = "pass"})

return xdp.program(function(ctx)
	return action.DROP
end, {name = "drop", default = action.ABORTED})

