local linux = require("linux")
local string = require("string")

local common = {}

local udp = 0x11
local dns = 0x35  -- DNS port 53
local eth_len = 14

-- Target domain: test.internal
local target_dns = string.pack("s1s1", "test", "internal")

-- Target IP: 127.0.0.1
local target_ip = 0x7F000001  -- 127.0.0.1 in network byte order (big-endian)

local function get_domain(skb, off)
	local _, nameoff, name = skb:getstring(off):find("([^\0]*)")
	return name, nameoff + 1
end

local function calculate_ip_checksum(skb, ip_off, ip_len)
	-- Zero out the checksum field first
	skb:setuint16(ip_off + 10, 0)

	local sum = 0
	-- Sum all 16-bit words in the IP header
	for i = 0, ip_len - 1, 2 do
		sum = sum + skb:getuint16(ip_off + i)
	end

	-- Fold 32-bit sum to 16 bits
	while (sum >> 16) > 0 do
		sum = (sum & 0xFFFF) + (sum >> 16)
	end

	return ~sum & 0xFFFF
end

local function calculate_udp_checksum(skb, ip_off, ihl, udp_off, udp_len)
	-- Get source and destination IP addresses
	local src_ip = skb:getuint32(ip_off + 12)
	local dst_ip = skb:getuint32(ip_off + 16)

	-- Zero out the UDP checksum field first
	skb:setuint16(udp_off + 6, 0)

	local sum = 0

	-- Add pseudo-header
	sum = sum + ((src_ip >> 16) & 0xFFFF)
	sum = sum + (src_ip & 0xFFFF)
	sum = sum + ((dst_ip >> 16) & 0xFFFF)
	sum = sum + (dst_ip & 0xFFFF)
	sum = sum + udp  -- Protocol
	sum = sum + udp_len  -- UDP length

	-- Add UDP header and data
	for i = 0, udp_len - 1, 2 do
		sum = sum + skb:getuint16(udp_off + i)
	end

	-- Fold 32-bit sum to 16 bits
	while (sum >> 16) > 0 do
		sum = (sum & 0xFFFF) + (sum >> 16)
	end

	local checksum = ~sum & 0xFFFF
	-- UDP checksum of 0x0000 should be sent as 0xFFFF
	if checksum == 0 then
		checksum = 0xFFFF
	end

	return checksum
end

function common.hook(skb, action)
	-- Get protocol from IP header (offset 9)
	local proto = skb:getuint8(eth_len + 9)

	-- Only process UDP packets
	if proto ~= udp then
		return action.ACCEPT
	end

	-- Get IP header length (IHL field in first byte of IP header)
	local ihl = skb:getuint8(eth_len) & 0x0F
	local thoff = eth_len + ihl * 4  -- Transport header offset

	-- Check if destination port is DNS (53) - this means it's a DNS query
	local dstport = linux.ntoh16(skb:getuint16(thoff + 2))
	if dstport ~= dns then
		return action.ACCEPT
	end

	-- DNS payload starts after UDP header (8 bytes)
	local dnsoff = thoff + 8

	-- Get number of additional records (might include EDNS0)
	local nadditional = linux.ntoh16(skb:getuint16(dnsoff + 10))

	-- Skip DNS header (12 bytes) to get to question section
	local question_off = dnsoff + 12

	-- Parse domain name from question section
	local domainname, nameoff = get_domain(skb, question_off)

	-- Check if this is the domain we want to respond to
	if domainname == target_dns then
		print("dnsrewrite: intercepted query for test.internal, rewriting response")

		-- Get the transaction ID from the query
		local txid = skb:getuint16(dnsoff)

		-- Get query type and class
		local qtype = skb:getuint16(question_off + nameoff)
		local qclass = skb:getuint16(question_off + nameoff + 2)

		-- Only respond to A record queries (type 1)
		local query_type = linux.ntoh16(qtype)
		if query_type ~= 1 then
			return action.ACCEPT
		end

		-- Swap IP addresses (source <-> destination)
		local src_ip = skb:getuint32(eth_len + 12)
		local dst_ip = skb:getuint32(eth_len + 16)
		skb:setuint32(eth_len + 12, dst_ip)  -- New source = old dest
		skb:setuint32(eth_len + 16, src_ip)  -- New dest = old source

		-- Swap UDP ports (source <-> destination)
		local src_port = skb:getuint16(thoff)
		local dst_port = skb:getuint16(thoff + 2)
		skb:setuint16(thoff, dst_port)  -- New source port = old dest (53)
		skb:setuint16(thoff + 2, src_port)  -- New dest port = old source

		-- Build DNS response header
		-- Flags: Standard query response, no error
		-- QR=1 (response), Opcode=0 (standard query), AA=1 (authoritative)
		-- TC=0, RD=1 (recursion desired, copied from query), RA=1, Z=0, RCODE=0
		local flags = 0x8580  -- Binary: 1000 0101 1000 0000
		skb:setuint16(dnsoff + 2, linux.hton16(flags))

		-- Set question count = 1 (already present in query)
		-- Set answer count = 1
		skb:setuint16(dnsoff + 6, linux.hton16(1))

		-- Set authority count = 0
		skb:setuint16(dnsoff + 8, linux.hton16(0))

		-- Set additional count = 0
		skb:setuint16(dnsoff + 10, linux.hton16(0))

		-- Answer section starts after question section
		local answer_off = question_off + nameoff + 4

		-- Calculate required packet size
		-- DNS response = header (12) + question (nameoff + 4) + answer (16)
		local new_dns_len = 12 + nameoff + 4 + 16
		local new_udp_len = 8 + new_dns_len
		local new_ip_len = ihl * 4 + new_udp_len
		local new_total_len = eth_len + new_ip_len

		-- Get current packet length
		local curr_ip_len = linux.ntoh16(skb:getuint16(eth_len + 2))
		local curr_total_len = eth_len + curr_ip_len

		-- Expand packet if needed
		local expand_bytes = new_total_len - curr_total_len
		if expand_bytes > 0 then
			skb:expand(expand_bytes)
		end

		-- Answer format:
		-- Name: Use pointer to question name (2 bytes: 0xC00C points to offset 12)
		skb:setuint16(answer_off, linux.hton16(0xC00C))

		-- Type: A record (1)
		skb:setuint16(answer_off + 2, linux.hton16(1))

		-- Class: IN (1)
		skb:setuint16(answer_off + 4, linux.hton16(1))

		-- TTL: 300 seconds (5 minutes)
		skb:setuint32(answer_off + 6, linux.hton32(300))

		-- Data length: 4 bytes (IPv4 address)
		skb:setuint16(answer_off + 10, linux.hton16(4))

		-- IP address: 127.0.0.1
		skb:setuint32(answer_off + 12, linux.hton32(target_ip))

		-- Calculate new packet length
		-- DNS response = header (12) + question (nameoff + 4) + answer (16)
		local dns_len = 12 + nameoff + 4 + 16
		local udp_len = 8 + dns_len
		local ip_len = ihl * 4 + udp_len

		-- Update UDP length
		skb:setuint16(thoff + 4, linux.hton16(udp_len))

		-- Update IP total length
		skb:setuint16(eth_len + 2, linux.hton16(ip_len))

		-- Recalculate UDP checksum
		local udp_csum = calculate_udp_checksum(skb, eth_len, ihl, thoff, udp_len)
		skb:setuint16(thoff + 6, linux.hton16(udp_csum))

		-- Recalculate IP checksum
		local ip_csum = calculate_ip_checksum(skb, eth_len, ihl * 4)
		skb:setuint16(eth_len + 10, linux.hton16(ip_csum))

		-- Accept the packet (it will be delivered to the querying application)
		return action.ACCEPT
	end

	-- For non-matching domains, allow the query to proceed normally
	return action.ACCEPT
end

return common
