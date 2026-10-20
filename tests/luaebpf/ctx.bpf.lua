--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the ctx case (see ctx.sh).

local corpus = require("tests.luaebpf.corpus")

-- loopback, whose generic rx queue 0 has its xdp_rxq registered on every device, which is what
-- xdp_convert_md_to_buff requires of a non-zero ingress_ifindex (net/bpf/test_run.c)
local IFINDEX <const> = 1
local QUEUE   <const> = 0
local FRAME   <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00"

local function ingress(ctx)
	local ifindex = ctx:ingress()
	return ifindex
end

local function queue(ctx)
	local index = ctx:queue()
	return index
end

local function both(ctx)
	return ctx:ingress() * 100 + ctx:queue()
end

local xdpctx = corpus.context("xdpctx", "xdp_md",
	{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, FRAME)

local rows = corpus.new()
rows:declare("ingress", ingress, nil, xdpctx)
rows:declare("queue", queue, nil, xdpctx)
rows:declare("both", both, nil, xdpctx)
rows:close()

