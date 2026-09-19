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

local shouldstop = thread.shouldstop
local DONTWAIT   = socket.msg.DONTWAIT

-- LLDP multicast destination
local ETH_DST_MAC = string.char(0x01,0x80,0xc2,0x00,0x00,0x0e)
-- System Capabilities: station only
local LLDP_CAP_STATION_ONLY = 0x0080
local RX_LEN <const> = 2048
local POLL_MS <const> = 10

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
		tlv(1, chassis_id, 4),
		tlv(2, port_id, 5),
		tlv(3, ttl),
		tlv(4, config.port_description),
		tlv(5, config.system.name),
		tlv(6, config.system.description),
		tlv(7, capabilities),
		-- End of LLDPDU
		tlv(0, ""),
	}

	return table.concat(pdu)
end

local function macaddr(addr)
	if #addr ~= 6 then
		return
	end
	return string.format("%02x:%02x:%02x:%02x:%02x:%02x", addr:byte(1, 6))
end

local function identifier(payload)
	if #payload < 2 then
		return
	end
	local subtype = payload:byte(1)
	local value = payload:sub(2)
	if subtype == 3 or subtype == 4 then
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
	nbr.chassis = identifier(payload)
end

local function port_id(nbr, payload)
	nbr.port = identifier(payload)
end

local function take_ttl(nbr, payload)
	if #payload == 2 then
		nbr.ttl = string.unpack(">I2", payload)
	end
end

local function system_name(nbr, payload)
	nbr.name = payload
end

local decode = {
	[1] = chassis_id,
	[2] = port_id,
	[3] = take_ttl,
	[5] = system_name,
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
		if t == 0 then
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
	return nbr.chassis, nbr.port, nbr.name or "", src
end

local function remember_neighbor(neighbors, chassis, port, name)
	local key = chassis .. "@" .. port
	neighbors[key] = { port = port, name = name }
	print(string.format("[lldpd] neighbor port=%s name=%s", port, name))
end

local ifindex = linux.ifindex(config.interface)
local src_mac = linux.ifaddr(ifindex)
local lldp_frame = build_lldp_frame(src_mac)
local tx_interval_ns = config.tx_interval_ms * 1000000

local function worker()
	local sock <close> = raw.bind(eth.LLDP, ifindex)
	local neighbors = {}
	local last_tx = 0

	while (not shouldstop()) do
		local ok, data = pcall(sock.receive, sock, RX_LEN, DONTWAIT)
		if ok then
			print(string.format("[lldpd] rx %d bytes on ifindex=%d", #data, ifindex))
			local chassis, port, name, src = parse_lldp(data)
			if chassis ~= nil and src ~= src_mac then
				remember_neighbor(neighbors, chassis, port, name)
			end
		else
			if data ~= "EAGAIN" then
				error(data)
			end
		end

		local now = linux.time()
		if last_tx == 0 or (now - last_tx) >= tx_interval_ns then
			sock:send(lldp_frame)
			print(string.format("[lldpd] frame sent on ifindex=%d (%d bytes)", ifindex, #lldp_frame))
			last_tx = now
		end

		linux.schedule(POLL_MS)
	end

	print("[lldpd] worker stopped")
end

return worker

