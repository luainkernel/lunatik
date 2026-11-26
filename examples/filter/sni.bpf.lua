--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local xdp     = require("bpf.xdp")
local lunatik = require("lunatik")
local struct  = require("struct")
local vmlinux = require("bpf.vmlinux")
local action  = require("linux.xdp").action
local eth     = require("linux.eth")
local ipproto = require("linux.socket").ipproto

local HTTPS <const> = 443
local WORD  <const> = 4

local ethhdr = struct(vmlinux.layout("ethhdr"))
local iphdr  = struct(vmlinux.layout("iphdr"))
local tcphdr = struct(vmlinux.layout("tcphdr"))

local sni = lunatik.runtime("examples/filter/sni")

-- a frame too short for the headers it reads passes, since a read past its end would drop it
local function filter_https(ctx)
	local p = ctx:packet()
	if #p < eth.HLEN + iphdr.size or ethhdr:view(p, 0).h_proto ~= eth.proto.IP then
		return action.PASS
	end
	local ip = iphdr:view(p, eth.HLEN)
	local at = eth.HLEN + ip.ihl * WORD
	if ip.protocol ~= ipproto.TCP or #p < at + tcphdr.size then
		return action.PASS
	end
	local tcp = tcphdr:view(p, at)
	local payload = at + tcp.doff * WORD
	if tcp.dest ~= HTTPS or tcp.psh == 0 or payload >= #p then
		return action.PASS
	end
	return sni:run(payload) or action.PASS
end

return xdp.program(filter_https, {default = action.PASS})

