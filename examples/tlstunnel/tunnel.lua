--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local net    = require("net")
local thread = require("thread")
local tunnel = require("tunnel")
local common = require("examples.tlstunnel.common")

local match = string.match

-- bound here rather than in the thread body, so a port already taken is
-- reported by the spawn that binds it
local listener = common.listener(common.plainport)

-- the plaintext hook, where a policy or a rewrite in Lua would live: this one
-- only reports the first line of every payload that crosses, either way
local function inspect(data)
	print("tlstunnel relay: " .. match(data, "^[^\r\n]*"))
	return data
end

-- one client, relayed to a freshly keyed upstream leg until either end closes
local function serve(client)
	local upstream <close> = common.tcp()
	-- the peer is a listener on loopback, so this completes or is refused at once
	upstream:connect(net.aton(common.address), common.upstreamport)
	common.key(upstream)
	tunnel.body(client, upstream, {transform = inspect})()
end

local function relay()
	while not thread.shouldstop() do
		local client <close> = common.accept(listener)
		if client ~= nil then
			-- a refused upstream or a peer that resets raises, and one connection's failure is not the loop's
			local ok, err = pcall(serve, client)
			if not ok then
				print("tlstunnel relay: connection failed: " .. err)
			end
		end
	end
end

return relay

