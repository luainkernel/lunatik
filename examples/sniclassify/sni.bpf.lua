--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local tc      = require("bpf.tc")
local map     = require("bpf.map")
local lunatik = require("lunatik")
local action  = require("linux.tc").action
local https   = require("examples.common.https")

local FLOWS <const> = 65536

-- LRU: a full hash map refuses the update of a new flow, which stops the program and drops the packet
local flows = map.lru_hash("flows", {key = "I4", value = "I4", entries = FLOWS})
local sni   = lunatik.runtime("examples/sniclassify/sni")

local function classify(skb)
	local hash = skb:hash()
	local priority = flows[hash]
	if priority then
		skb:priority(priority)
		return action.OK
	end
	local p = skb:data()
	local payload = https.payload(p)
	if payload == https.NONE then
		return action.OK
	end
	local verdict = sni:run(payload)
	if verdict == nil then
		return action.OK
	end
	flows[hash] = skb:priority()
	return verdict
end

return tc.program(classify, {egress = true, default = action.OK})

