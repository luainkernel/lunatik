--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the handshake timeout test (see timeout.sh).

local socket    = require("socket")
local net       = require("net")
local netlink   = require("netlink")
local message   = require("netlink.message")
local handshake = require("handshake")
local sk        = require("linux.socket")
local ctrl      = require("linux.genl")

local pack = string.pack

-- uapi/linux/netlink.h; linux.netlink carries the protocol numbers alone
local ADD_MEMBERSHIP <const> = 1
local LOCALHOST      <const> = "127.0.0.1"
local FAMILY         <const> = "handshake"
local GROUP          <const> = "tlshd"
local TIMEOUT        <const> = 300

local function tcpsocket()
	return socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
end

-- CTRL_ATTR_MCAST_GRP_ID reports the global group number, which is the one
-- genl_has_listeners asks netlink about and the one a subscription names
local function groupid(session, family, group)
	local msgs = session:call(ctrl.id.CTRL, ctrl.cmd.GETFAMILY, 0,
		message.attrs{[ctrl.attr.FAMILY_NAME] = pack("z", family)})
	for _, msg in ipairs(msgs) do
		local groups = msg.attrs[ctrl.attr.MCAST_GROUPS]
		if groups then
			for _, nested in pairs(message.attrs(groups, 1)) do
				local fields = message.attrs(nested, 1)
				if message.str(fields[ctrl.attr.MCAST_GRP_NAME]) == group then
					return message.u32(fields[ctrl.attr.MCAST_GRP_ID])
				end
			end
		end
	end
end

local session = netlink.genl()
local id = groupid(session, FAMILY, GROUP)
assert(id, "the " .. FAMILY .. " family publishes no " .. GROUP .. " multicast group")
session.socket:setsockopt(sk.sol.NETLINK, ADD_MEMBERSHIP, id)

local server = tcpsocket()
server:bind(net.aton(LOCALHOST), 0)
server:listen()
local _, port = server:getsockname()

local client = tcpsocket()
client:connect(net.aton(LOCALHOST), port)

local ok, err = pcall(handshake.client, client, {timeout = TIMEOUT})
assert(not ok and err == "ETIMEDOUT", "a request nobody accepts should raise ETIMEDOUT, got " .. tostring(err))
print("handshake timeout: a queued request times out")

-- the cancel takes the request off the pending list but leaves it keyed on the
-- socket, so the kernel refuses a second hello until the socket is destroyed
ok, err = pcall(handshake.client, client, {timeout = TIMEOUT})
assert(not ok and err == "EBUSY", "a second hello on the same socket should raise EBUSY, got " .. tostring(err))
print("handshake timeout: a second hello on the timed-out socket is refused")

client:close()
print("handshake timeout: the socket closes after the timeout")

session:close()

local fresh = tcpsocket()
fresh:connect(net.aton(LOCALHOST), port)
ok, err = pcall(handshake.client, fresh, {timeout = TIMEOUT})
assert(not ok and err == "ESRCH", "with no subscriber left the hello should raise ESRCH, got " .. tostring(err))
print("handshake timeout: the subscriber alone decides between the wait and ESRCH")

fresh:close()
server:close()

