-- see ctx.sh
local corpus  = require("tests.luaebpf.corpus")
local vmlinux = require("luaebpf.vmlinux")
local tc      = require("bpf.tc")

-- loopback, whose generic rx queue 0 has its xdp_rxq registered on every device, which is what
-- xdp_convert_md_to_buff requires of a non-zero ingress_ifindex (net/bpf/test_run.c)
local IFINDEX <const> = 1
local QUEUE   <const> = 0
-- prog run builds the skb on loopback unless ctx_in names a device above it, so skb.ifindex
-- reads loopback's whatever the context says
local INGRESS <const> = 3
local PRIO    <const> = 5
local WRITTEN <const> = 77
local FRAME   <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00"

local function ingress(ctx)
	return ctx.ingress_ifindex
end

local function queue(ctx)
	return ctx.rx_queue_index
end

local function both(ctx)
	return ctx.ingress_ifindex * 100 + ctx.rx_queue_index
end

local function skblen(skb)
	return skb.len
end

local function skbifindex(skb)
	return skb.ifindex
end

local function skbingress(skb)
	return skb.ingress_ifindex
end

local function skbpriority(skb)
	return skb.priority
end

-- prog run cannot supply a hash: it sits in a range convert___skb_to_skb makes ctx_in leave
-- zero, and the skb it builds has none. The row is here for the read, not for the number
local function skbhash(skb)
	return skb.hash
end

-- the read comes back through the kernel's own context, so it answers what the store landed on
local function skbsetpriority(skb)
	skb.priority = WRITTEN
	return skb.priority
end

local xdpctx = corpus.context("xdpctx", "xdp_md",
	{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, FRAME)
local skbctx = corpus.context("skbctx", "__sk_buff",
	{ingress_ifindex = INGRESS, ifindex = IFINDEX, priority = PRIO, hash = 0}, FRAME)
-- the write row gets a context of its own, since it leaves its twin's priority changed
local skbwrite = corpus.context("skbwrite", "__sk_buff",
	{ingress_ifindex = INGRESS, ifindex = IFINDEX, priority = PRIO, hash = 0}, FRAME)

local sched = {program = tc.program}

local rows = corpus.new()
rows:declare("ingress", ingress, nil, xdpctx)
rows:declare("queue", queue, nil, xdpctx)
rows:declare("both", both, nil, xdpctx)
rows:declare("skblen", skblen, sched, skbctx)
rows:declare("skbifindex", skbifindex, sched, skbctx)
rows:declare("skbingress", skbingress, sched, skbctx)
rows:declare("skbpriority", skbpriority, sched, skbctx)
rows:declare("skbhash", skbhash, sched, skbctx)
rows:declare("skbsetprio", skbsetpriority, sched, skbwrite)
rows:close()

-- what the case reads ctx_out back at, from the same BTF the emitter lowered the store against
local out = assert(io.open("offsets.txt", "w"))
for _, field in ipairs(vmlinux.layout("__sk_buff").fields) do
	out:write(field.name, "\t", field.offset, "\t", field.size, "\n")
end
out:write("written\t", WRITTEN, "\t0\n")
out:close()

