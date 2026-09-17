-- see bounds.sh
local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")
local action  = require("linux.xdp")

local CEILING <const> = 70000 -- above the last offset the verifier lets a packet pointer take
local DEEP    <const> = 120   -- inside the whole ClientHello's SNI, past the truncated one
local IFINDEX <const> = 1
local QUEUE   <const> = 0

local makers = {}

-- one byte past the last, which the interpreter raises on and the bounds check refuses
function makers.past() return function(ctx) local p = ctx:packet() local v = p:getbyte(#p) return v end end
function makers.high() return function(ctx) local p = ctx:packet() local v = p:getbyte(CEILING) return v end end
function makers.deep() return function(ctx) local p = ctx:packet() local v = p:getuint16(DEEP) return v end end

local order = {"past", "high", "deep"}

local contexts = {}
for _, name in ipairs(packets.order) do
	contexts[name] = corpus.context(name, "xdp_md",
		{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, packets[name])
end

-- each row twice, under either default, so the answer is the verdict the file asked for rather
-- than a number the failure path happens to leave behind
local rows = corpus.new()
for _, op in ipairs(order) do
	for i, name in ipairs(packets.order) do
		rows:declare(op .. i, makers[op](), {default = action.DROP}, contexts[name])
		rows:declare(op .. "pass" .. i, makers[op](), {default = action.PASS}, contexts[name])
	end
end
rows:close()

