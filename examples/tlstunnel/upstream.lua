--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local linux  = require("linux")
local thread = require("thread")
local common = require("examples.tlstunnel.common")
local sk     = require("linux.socket")

local match = string.match

local DONTWAIT <const> = sk.msg.DONTWAIT
local EAGAIN   <const> = "EAGAIN"
local READMAX  <const> = 4096
-- milliseconds a read that found nothing yields before it polls again
local POLL     <const> = 10
local REPLY    <const> = "HTTP/1.0 200 OK\r\n\r\nhello from the kTLS upstream\r\n"

local listener = common.listener(common.upstreamport)

-- one request; nil where the thread was stopped or the client closed first
local function request(conn)
	while not thread.shouldstop() do
		local ok, data, record = pcall(conn.receiverecord, conn, READMAX, DONTWAIT)
		if ok then
			-- an empty read is the orderly close of a client that wrote nothing
			if #data == 0 then
				return nil
			end
			return data, record
		end
		if data ~= EAGAIN then
			error(data, 0)
		end
		linux.schedule(POLL)
	end
end

-- the record type is reported beside the bytes: on a leg that is not keyed it
-- is nil, so 23 is the reading that the record layer ran
local function serve(conn)
	common.key(conn)
	local data, record = request(conn)
	if data ~= nil then
		print("tlstunnel upstream: read " .. match(data, "^[^\r\n]*") .. " as record " .. tostring(record))
		conn:send(REPLY)
	end
end

local function upstream()
	while not thread.shouldstop() do
		local conn <close> = common.accept(listener)
		if conn ~= nil then
			-- a stray connection raises on the keying or the read, and one connection's failure is not the loop's
			local ok, err = pcall(serve, conn)
			if not ok then
				print("tlstunnel upstream: connection failed: " .. err)
			end
		end
	end
end

return upstream

