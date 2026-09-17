-- see nobtf.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")

local lua = xdp.runtime()

-- the object is compiled with LUAEBPF_DROP=ksyms, so it never loads; the nil branch is here
-- because the compiler refuses the answer as a number without it
return xdp.program(function(ctx)
	local verdict = lua(0)
	if verdict then
		return verdict
	end
	return action.PASS
end, {name = "nobtf"})

