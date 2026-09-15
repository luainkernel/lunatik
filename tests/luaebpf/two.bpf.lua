-- see undo.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")

xdp.program(function(ctx)
	return action.PASS
end, {name = "first"})

return xdp.program(function(ctx)
	return action.PASS
end, {name = "second"})

