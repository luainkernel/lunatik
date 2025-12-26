--
-- SPDX-FileCopyrightText: (c) 2025 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Daemon to send LLDP frames on given interface
local socket = require("socket")
local linux  = require("linux")
local thread = require("thread")

local shouldstop = thread.shouldstop

local ETH_P_ALL  = 0x0003

local config = {
    interface = "veth0",
    tx_interval_ms = 30000, -- transmission interval in ms
    system = {
        name = "lunatik-lldpd",
        description = "LLDP daemon implemented in Lunatik",
        ttl = 120,
        capabilities = 0x0080, -- system capabilities: station only
        capabilities_enabled = 0x0080,
    },
    lldp = {
		-- LLDP multicast destination
        dst_mac = string.char(0x01,0x80,0xc2,0x00,0x00,0x0e),
        ethertype = 0x88cc,
    },
}

local function get_src_mac(ifindex)
    local rx = socket.new(socket.af.PACKET, socket.sock.RAW, ETH_P_ALL)
	rx:bind(string.pack(">H", ETH_P_ALL), ifindex)

    local frame = rx:receive(2048)
	rx:close()

    return frame:sub(7, 12)
end

local function tlv(t, value)
    return string.pack(">H", (t << 9) | #value) .. value
end

local function build_lldp_frame(src, ifindex)
    local chassis_tlv =
        string.pack(">H", (1 << 9) | 6) .. src

    local port_tlv = tlv(2, string.char(5) .. config.interface)

    local ttl_tlv =
        string.pack(">H", (3 << 9) | 2) ..
        string.pack(">H", config.system.ttl)

	local sys_name_tlv = tlv(6, config.system.name)

	local sys_desc_tlv = tlv(6, config.system.description)

	-- system capabilities
	-- https://datatracker.ietf.org/doc/html/rfc4957#section-3.4.3
	local sys_caps_tlv =
    string.pack(">H", (7 << 9) | 4) ..
    string.pack(">H", config.system.capabilities) ..
    string.pack(">H", config.system.capabilities_enabled)

    local end_tlv = string.pack(">H", 0)

	local lldp_payload =
        chassis_tlv ..
        port_tlv ..
        ttl_tlv ..
        sys_name_tlv ..
        sys_desc_tlv ..
		sys_caps_tlv ..
        end_tlv

    local eth_hdr =
        config.lldp.dst_mac ..
        src ..
        string.pack(">H", config.lldp.ethertype)

    return eth_hdr .. lldp_payload
end

local ifindex = linux.ifindex(config.interface)

local src_mac = get_src_mac(ifindex)
local lldp_frame = build_lldp_frame(src_mac, ifindex)

local function worker()
    local tx <close> = socket.new(socket.af.PACKET, socket.sock.RAW, config.lldp.ethertype)
    tx:bind(ifindex)

    while (not shouldstop()) do
        tx:send(lldp_frame)
        print(string.format("[lldpd] frame sent on %s: %s", ifindex, lldp_frame))
        linux.schedule(30000)
    end

    print("[lldpd] worker stopped")
end

return worker

