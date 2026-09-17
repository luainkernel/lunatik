-- see btfview.sh
local vmlinux = require("luaebpf.vmlinux")
local xdp     = require("bpf.xdp")

local out = assert(io.open("layout.txt", "w"))
for _, what in ipairs({"xdp_md", "__sk_buff", "iphdr"}) do
	local layout = vmlinux.layout(what)
	out:write("size\t", what, "\t", layout.size, "\n")
	for _, field in ipairs(layout.fields) do
		out:write("field\t", what, "\t", field.name, "\t", field.offset, "\t", field.size, "\n")
	end
end
local ok, message = pcall(vmlinux.layout, "a_struct_no_kernel_publishes")
out:write("missing\t", tostring(ok), "\t", message, "\n")
out:close()

return xdp.program(function(ctx) return 2 end)

