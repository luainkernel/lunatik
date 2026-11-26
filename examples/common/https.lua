--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
--- The HTTPS payload the packet-filtering examples' programs hand their kernel scripts.
-- @module examples.common.https

local struct  = require("struct")
local vmlinux = require("bpf.vmlinux")
local eth     = require("linux.eth")
local ipproto = require("linux.socket").ipproto

local HTTPS <const> = 443
local WORD  <const> = 4
local NONE  <const> = 0

local ethhdr = struct(vmlinux.layout("ethhdr"))
local iphdr  = struct(vmlinux.layout("iphdr"))
local tcphdr = struct(vmlinux.layout("tcphdr"))

local https = {}

--- What `https.payload` answers for a frame that carries no such payload, since none starts at its first byte.
https.NONE = NONE

--- Returns the offset of the payload a frame pushes to TCP port 443 over IPv4, or `https.NONE`.
-- A frame too short for a header it reads has none, since a compiled read past its end drops it.
-- @tparam userdata p the frame, as `ctx:packet()` or `skb:data()` gives it
-- @treturn integer the payload's offset
function https.payload(p)
	if #p < eth.HLEN + iphdr.size or ethhdr:view(p, 0).h_proto ~= eth.proto.IP then
		return NONE
	end
	local ip = iphdr:view(p, eth.HLEN)
	local at = eth.HLEN + ip.ihl * WORD
	if ip.protocol ~= ipproto.TCP or #p < at + tcphdr.size then
		return NONE
	end
	local tcp = tcphdr:view(p, at)
	local payload = at + tcp.doff * WORD
	if tcp.dest ~= HTTPS or tcp.psh == 0 or payload >= #p then
		return NONE
	end
	return payload
end

return https

