-- see undo.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")

return xdp.program(function(ctx)
	return action.PASS
end, {name = "raiser"})

