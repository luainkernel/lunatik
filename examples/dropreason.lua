-- Answers "why is my packet dying?". A kprobe on kfree_skb_reason() -- the
-- choke point every dropped skb goes through -- reads the drop reason from
-- the probed function's arguments and counts drops by name (linux.dropreason)
-- in an RCU table published on the shared environment (lunatik._ENV), where
-- any runtime -- including the REPL -- can query it live.
--
-- Usage:
--   sudo lunatik run examples/dropreason hardirq
--   sudo lunatik                                  # opens the kernel REPL
--   > drops = lunatik._ENV.dropreason
--   > drops.NO_SOCKET
--   16
--   > t = {} require("rcu").map(drops, function(k, v) table.insert(t, string.format("%7d  %s", v, k)) end)
--   > table.sort(t) return table.concat(t, "\n")
--
-- Set WATCH below to also trap the first hit of one reason, dumping the
-- registers and call trace of the exact drop site to dmesg.

local probe  = require("probe")
local rcu    = require("rcu")
local reason = require("linux.dropreason")
local env    = require("lunatik")._ENV

local WATCH -- = "NO_SOCKET"

local CONSUMED <const> = reason.CONSUMED -- freed, not dropped

local name = {}
for k, v in pairs(reason) do name[v] = k end

local track = rcu.table()
env.dropreason = track

local caught = false

local function pre(symbol, dump, argument)
	local r = argument(1)
	if r == CONSUMED then
		return
	end
	local key = name[r] or "UNKNOWN"
	track[key] = (track[key] or 0) + 1
	if key == WATCH and not caught then
		caught = true
		print("dropreason: caught " .. WATCH .. ", registers:")
		dump()
	end
end

local handlers = {pre = pre}
handlers.sentinel = setmetatable({}, {__gc = function()
	env.dropreason = nil
end})
probe.new("kfree_skb_reason", handlers)

