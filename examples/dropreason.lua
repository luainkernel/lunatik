-- Answers "why is my packet dying?". A kprobe on kfree_skb_reason() -- the
-- choke point every dropped skb goes through -- reads the drop reason from
-- the probed function's arguments and counts drops by name (linux.dropreason)
-- in an RCU table published on the shared environment (lunatik._ENV), where
-- any runtime -- including the REPL -- can query it live.
--
-- Usage:
--   sudo lunatik run examples/dropreason hardirq
--   echo x > /dev/udp/127.0.0.1/9999              # trigger a NO_SOCKET drop
--   sudo lunatik                                  # opens the kernel REPL
--   > drops = lunatik._ENV.dropreason
--   > drops.NO_SOCKET
--   16
--   > return require("examples.dropreason_report")(drops)   # counts by reason

local probe  = require("probe")
local rcu    = require("rcu")
local reason = require("linux.dropreason")
local env    = require("lunatik")._ENV

-- WATCH traps one drop reason: on its first occurrence, the register dump and
-- call trace of that exact drop site are printed to dmesg. Set it to any reason
-- name from linux.dropreason (e.g. "NO_SOCKET", "NETFILTER_DROP", "TCP_CSUM").
local WATCH
-- local WATCH = "NO_SOCKET"

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

