--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side fixture for the compiled SNI classifier example (see example_sniclassify.sh).

local linux   = require("linux")
local raw     = require("socket.raw")
local packets = require("tests.luaebpf.packets")
local eth     = require("linux.eth")

local DEV     <const> = "classify0" -- the device the example classifies the egress of
local CLASSED <const> = "netflix.com" -- a name examples/sniclassify/sni.lua's policy carries
local FLOW    <const> = 2 -- frames of one flow, so the second is the one decided from the map

-- the packet the header walk rejects goes first: nothing is cached yet, so what it takes is the
-- qdisc's default class rather than a decision the classifier made for another packet
local wire <close> = raw.bind(eth.ALL, linux.ifindex(DEV))
wire:send(packets.icmp)

local hello = packets.clienthello(CLASSED)
for _ = 1, FLOW do
	wire:send(hello)
end

print("luaebpf sniclassify: sent " .. (FLOW + 1) .. " frames on " .. DEV)

