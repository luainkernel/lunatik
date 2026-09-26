--
-- SPDX-FileCopyrightText: (c) 2025-2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Daemon to send LLDP frames on given interface, receive them, and remember neighbors.
local raw    = require("socket.raw")
local linux  = require("linux")
local thread = require("thread")
local eth    = require("linux.eth")
local socket = require("linux.socket")
local rcu    = require("rcu")
local struct = require("struct")
local env    = require("lunatik")._ENV

local shouldstop = thread.shouldstop
local timeval    = struct(socket.layout.timeval)

-- LLDP multicast destination
local ETH_DST_MAC = string.char(0x01,0x80,0xc2,0x00,0x00,0x0e)
-- System Capabilities: station only
local LLDP_CAP_STATION_ONLY = 0x0080
local RX_LEN <const> = 2048
local RCVTIMEO_SEC <const> = 1
local CHASSIS_MAC <const> = 4
local PORT_MAC <const> = 3

local types = {
	end_pdu = 0,
	chassis_id = 1,
	port_id = 2,
	ttl = 3,
	port_desc = 4,
	system_name = 5,
	system_desc = 6,
	capabilities = 7,
}

local config = {
	interface = "veth0",
	port_description = "ethernet interface",
	-- default transmission interval used in lldpd implementation (30s)
	-- https://lldpd.github.io/usage.html
	tx_interval_ms = 30000,
	system = {
		name = "lunatik-lldpd",
		description = "LLDP daemon implemented in Lunatik",
		ttl = 120,
		capabilities = LLDP_CAP_STATION_ONLY,
		capabilities_enabled = LLDP_CAP_STATION_ONLY,
	},
}

local ethertype = string.pack(">I2", eth.LLDP)

local function tlv(t, payload, subtype)
	if subtype then
		payload = string.char(subtype) .. payload
	end
	return string.pack(">I2", (t << 9) | #payload) .. payload
end

local function build_lldp_frame(chassis_id)
	local port_id = config.interface
	local ttl = string.pack(">I2", config.system.ttl)
	local capabilities = string.pack(">I2I2", config.system.capabilities, config.system.capabilities_enabled)

	local pdu = {
		-- Ethernet header
		ETH_DST_MAC,
		chassis_id,
		ethertype,
		-- LLDP TLVs
		tlv(types.chassis_id, chassis_id, CHASSIS_MAC),
		tlv(types.port_id, port_id, 5),
		tlv(types.ttl, ttl),
		tlv(types.port_desc, config.port_description),
		tlv(types.system_name, config.system.name),
		tlv(types.system_desc, config.system.description),
		tlv(types.capabilities, capabilities),
		-- End of LLDPDU
		tlv(types.end_pdu, ""),
	}

	return table.concat(pdu)
end

local function macaddr(addr)
	if #addr ~= 6 then
		return
	end
	return string.format("%02x:%02x:%02x:%02x:%02x:%02x", addr:byte(1, 6))
end

local function identifier(payload, mac_subtype)
	if #payload < 2 then
		return
	end
	local subtype = payload:byte(1)
	local value = payload:sub(2)
	if subtype == mac_subtype then
		return macaddr(value)
	end
	return value
end

local function next_tlv(pdu, i)
	if i + 1 > #pdu then
		return
	end
	local word = string.unpack(">I2", pdu, i)
	local t = word >> 9
	local len = word & 0x1ff
	if i + 1 + len > #pdu then
		return
	end
	return t, pdu:sub(i + 2, i + 1 + len), i + 2 + len
end

local function chassis_id(nbr, payload)
	nbr.chassis = identifier(payload, CHASSIS_MAC)
end

local function port_id(nbr, payload)
	nbr.port = identifier(payload, PORT_MAC)
end

local function ttl(nbr, payload)
	if #payload == 2 then
		nbr.ttl = string.unpack(">I2", payload)
	end
end

local function system_name(nbr, payload)
	nbr.name = payload
end

local decode = {
	[types.chassis_id] = chassis_id,
	[types.port_id] = port_id,
	[types.ttl] = ttl,
	[types.system_name] = system_name,
}

local function parse_lldp(frame)
	if #frame < 14 then
		return
	end
	local src = frame:sub(7, 12)
	local ethtype = string.unpack(">I2", frame, 13)
	if ethtype ~= eth.LLDP then
		return
	end

	local pdu = frame:sub(15)
	local nbr = {}
	local i = 1
	while true do
		local t, payload, j = next_tlv(pdu, i)
		if t == nil then
			return
		end
		if t == types.end_pdu then
			break
		end
		local take = decode[t]
		if take ~= nil then
			take(nbr, payload)
		end
		i = j
	end

	if nbr.chassis == nil or nbr.port == nil or nbr.ttl == nil then
		return
	end
	return nbr.chassis, nbr.port, nbr.name or "", src, nbr.ttl
end

local function drop_neighbor(seen, published, key, nbr)
	seen[key] = nil
	published[key] = nil
	print(string.format("[lldpd] neighbor dropped port=%s name=%s", nbr.port, nbr.name))
end

local function remember_neighbor(seen, published, chassis, port, name, hold)
	local key = chassis .. "@" .. port
	if hold == 0 then
		local nbr = seen[key]
		if nbr ~= nil then
			drop_neighbor(seen, published, key, nbr)
		end
		return
	end

	local nbr = seen[key]
	if nbr == nil then
		seen[key] = {port = port, name = name, ttl = hold, remaining = hold}
		published[key] = hold
		print(string.format("[lldpd] neighbor appears port=%s name=%s", port, name))
	elseif nbr.name ~= name or nbr.ttl ~= hold then
		seen[key] = {port = port, name = name, ttl = hold, remaining = hold}
		published[key] = hold
		print(string.format("[lldpd] neighbor changes port=%s name=%s", port, name))
	else
		nbr.remaining = hold
		published[key] = hold
	end
end

local function expire_neighbors(seen, published)
	for key, nbr in pairs(seen) do
		nbr.remaining = nbr.remaining - RCVTIMEO_SEC
		if nbr.remaining <= 0 then
			drop_neighbor(seen, published, key, nbr)
		else
			published[key] = nbr.remaining
		end
	end
end

local ifindex = linux.ifindex(config.interface)
local src_mac = linux.ifaddr(ifindex)
local lldp_frame = build_lldp_frame(src_mac)
local tx_interval_ns = config.tx_interval_ms * 1000000

local function worker()
	local sock <close> = raw.bind(eth.LLDP, ifindex)
	local seen = {}
	local published = rcu.table()
	env.lldpd = published
	local last_tx = 0

	sock:setsockopt(socket.sol.SOCKET, socket.so.RCVTIMEO_NEW, timeval:pack(RCVTIMEO_SEC, 0))

	while (not shouldstop()) do
		local now = linux.time()
		local ok, frame = pcall(sock.receive, sock, RX_LEN)
		if ok then
			local chassis, port, name, src, hold = parse_lldp(frame)
			if chassis ~= nil and src ~= src_mac then
				remember_neighbor(seen, published, chassis, port, name, hold)
			end
		elseif frame ~= "EAGAIN" and frame ~= "ETIMEDOUT" then
			error(frame)
		else
			expire_neighbors(seen, published)
		end

		if last_tx == 0 or (now - last_tx) >= tx_interval_ns then
			sock:send(lldp_frame)
			print(string.format("[lldpd] frame sent on ifindex=%d (%d bytes)", ifindex, #lldp_frame))
			last_tx = now
		end
	end

	env.lldpd = nil
	print("[lldpd] worker stopped")
end

return worker

