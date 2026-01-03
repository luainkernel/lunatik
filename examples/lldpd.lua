--
-- SPDX-FileCopyrightText: (c) 2025-2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Daemon to send LLDP frames on given interface
local raw    = require("socket.raw")
local linux  = require("linux")
local thread = require("thread")

local shouldstop = thread.shouldstop

local ETH_P_ALL  = 0x0003
local ETH_P_LLDP = 0x88cc

-- LLDP multicast destination
local ETH_DST_MAC = string.char(0x01,0x80,0xc2,0x00,0x00,0x0e)
-- System Capabilities: station only
local LLDP_CAP_STATION_ONLY = 0x0080

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

local ethertype = string.pack(">I2", ETH_P_LLDP)

local function get_src_mac()
	local rx <close> = raw.bind(ETH_P_ALL)
	local frame = rx:receive(2048)
	return frame:sub(7, 12)
end

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

local ifindex = linux.ifindex(config.interface)

local src_mac = get_src_mac()
local lldp_frame = build_lldp_frame(src_mac)

local function worker()
	local tx <close> = raw.bind(ETH_P_LLDP, ifindex)

	while (not shouldstop()) do
		tx:send(lldp_frame)
		print(string.format("[lldpd] frame sent on ifindex=%d (%d bytes)", ifindex, #lldp_frame))
		linux.schedule(config.tx_interval_ms)
	end

	print("[lldpd] worker stopped")
end

return worker

