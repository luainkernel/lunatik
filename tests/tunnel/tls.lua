--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side relay for the kTLS tunnel test (see tls.sh): plain.lua's relay
-- with its second end keyed.

local pair    = require("tests.tunnel.pair")
local session = require("tests.tls.session")
local tunnel  = require("tunnel")
local tls     = require("tls")
local ltls    = require("linux.tls")

local TLS13  <const> = tls.version.TLS_1_3
local AES128 <const> = ltls.cipher.AES_GCM_128

local listener = pair.listener()

return function()
	local a, b = pair.accept(listener)
	listener:close()
	if a == nil then
		return
	end
	-- before the relay's first send on it, and the peer keys its own end before it writes at all
	session.key(b, TLS13, AES128)
	tunnel.body(a, b)()
	print("tunnel tls: relay ended")
end

