--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

--- Attribute view over an `skb`: reads and writes packet fields as table keys
-- (`view.mark`, `view.priority`) instead of method calls. The wrapped packet
-- stays reachable as `view.skb`. Reading or writing a key other than `mark` and
-- `priority` raises `skb has no attribute '<key>'`.
-- @classmod skb.attr
-- @see skb
-- @usage
--   -- lunatik run -c softirq <script>: sets the priority of the IPv4 packets the host sends
--   local netfilter = require("netfilter")
--   local attr      = require("skb.attr")
--   local nf        = require("linux.nf")
--
--   local PRIORITY <const> = 3
--
--   local function classify(skb)
--     local view = attr.new(skb)
--     view.priority = PRIORITY
--     return nf.action.ACCEPT
--   end
--
--   netfilter.register{
--     hook     = classify,
--     pf       = nf.proto.IPV4,
--     hooknum  = nf.inet.LOCAL_OUT,
--     priority = nf.ip.pri.FILTER,
--   }

local fields <const> = {
	mark     = true,
	priority = true,
}

local attr = {}

local function checkfield(key)
	if not fields[key] then
		error("skb has no attribute '" .. key .. "'")
	end
end

function attr.__index(view, key)
	checkfield(key)
	local skb = view.skb
	return skb[key](skb)
end

function attr.__newindex(view, key, val)
	checkfield(key)
	local skb = view.skb
	skb[key](skb, val)
end

function attr.__len(view)
	return #view.skb
end

--- Wraps an `skb` in an attribute view.
-- @function attr.new
-- @static
-- @tparam skb skb the packet to view.
-- @treturn attr the attribute view.
function attr.new(skb)
	return setmetatable({skb = skb}, attr)
end

return attr

