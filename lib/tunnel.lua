--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- A plaintext relay between two connected sockets, as the body a `spawn`
-- script returns. Either side may be keyed for kTLS: the relay moves what
-- `socket:receiverecord` hands it, which is plaintext on a keyed socket and the
-- bytes themselves on a plain one, and the record layer re-encrypts wherever
-- the far side is keyed. A record that is not application data is read and
-- dropped, since its bytes sent on as plaintext would corrupt the far stream.
--
-- Every call the relay makes is bounded, which is what keeps one direction from
-- holding the other and brings each pass back to `thread.shouldstop`: the
-- receives carry `MSG_DONTWAIT` and the sends the `SO_SNDTIMEO` this module
-- installs on both sockets. What returns a send the stop finds already waiting
-- is the `TIF_NOTIFY_SIGNAL` `kthread_stop` raises from 6.1, not that bound:
-- below 6.1 `wait_woken` returns its timeout unchanged once
-- `kthread_should_stop` is set, so the bound stops elapsing and the wait spins.
--
-- @module tunnel
-- @see socket
-- @see thread
-- @see tls
-- @usage
-- local tunnel = require("tunnel")
--
-- return tunnel.body(client, upstream, {transform = inspect})

local linux  = require("linux")
local struct = require("struct")
local thread = require("thread")
local tls    = require("tls")
local sk     = require("linux.socket")

local sub = string.sub

local timeval = struct(sk.layout.timeval)

local DONTWAIT <const> = sk.msg.DONTWAIT
local DATA     <const> = tls.record.DATA
local EAGAIN   <const> = "EAGAIN"
local EINTR    <const> = "EINTR"

local SIZE      <const> = 4096
local IDLE      <const> = 10
local TIMEOUT   <const> = 100
local MS_PER_S  <const> = 1000
local US_PER_MS <const> = 1000

local tunnel = {}

local function boundsend(sock, ms)
	-- SO_SNDTIMEO refuses a tv_usec of a second or more, so the bound splits in two
	local bound = timeval:pack(ms // MS_PER_S, (ms % MS_PER_S) * US_PER_MS)
	sock:setsockopt(sk.sol.SOCKET, sk.so.SNDTIMEO_NEW, bound)
end

local function newdirection(from, to, transform)
	return {from = from, to = to, transform = transform, pending = "", closed = false}
end

-- a bounded send moves what it can; the tail it left behind is what the next
-- pass sends, so no byte of the stream is dropped by a short write
local function send(direction, data)
	local to = direction.to
	local ok, sent = pcall(to.send, to, data)
	if not ok then
		-- EINTR is the stop itself: from 6.1 kthread_stop's signal ends the wait a bounded send is in
		if sent ~= EAGAIN and sent ~= EINTR then
			error(sent, 0)
		end
		sent = 0
	end
	direction.pending = sub(data, sent + 1)
	return sent
end

-- one record, or nil where there is nothing to forward: an empty read is the
-- peer's orderly close, and a record the record layer typed as anything but
-- application data is not the far stream's to carry
local function receive(direction, size)
	local from = direction.from
	local ok, data, record = pcall(from.receiverecord, from, size, DONTWAIT)
	if not ok then
		if data ~= EAGAIN then
			error(data, 0)
		end
		return nil
	end
	if #data == 0 then
		direction.closed = true
		return nil
	end
	return (record == nil or record == DATA) and data or nil
end

-- what one direction moves in a pass, in bytes: the remainder of a short send
-- first, and a fresh record only once that remainder is out
local function move(direction, size)
	local pending = direction.pending
	if pending ~= "" then
		return send(direction, pending)
	end
	local data = receive(direction, size)
	if data == nil then
		return 0
	end
	local transform = direction.transform
	if transform then
		data = transform(data, direction.from)
		if data == nil then
			return 0
		end
	end
	return send(direction, data)
end

local function run(forward, backward, size, idle)
	while not thread.shouldstop() do
		local moved = move(forward, size) + move(backward, size)
		if forward.closed or backward.closed then
			return
		end
		-- yielding after a pass that moved bytes would cap throughput at one buffer per idle
		if moved == 0 then
			linux.schedule(idle)
		end
	end
end

---
-- Builds the thread body that relays between two connected sockets. Each pass
-- polls `thread.shouldstop` first, moves one record each way and yields only
-- when neither direction had anything; the body returns when the thread is
-- stopped or either peer closes, so from 6.1 a stop costs at most the pass it
-- lands in: `idle` and a bounded send each way. Installs `SO_SNDTIMEO` on both
-- sockets, since `socket:send` takes no flags and that is the only bound a
-- script can put on a send.
-- @function body
-- @tparam socket a one end of the relay.
-- @tparam socket b the other end.
-- @tparam[opt] table opts `size`, the bytes each receive asks for (4096), and
--   `timeout`, the milliseconds bounding each send (100), both of which must
--   be positive; `idle`, the milliseconds an idle pass yields (10); and
--   `transform`, called as `transform(data, from)` on every payload, whose
--   return is what is sent and whose absence drops the payload from the stream.
-- @treturn function the body a `spawn` script returns.
-- @raise Error when `size` or `timeout` is not positive, if a socket refuses
--   `SO_SNDTIMEO_NEW`, and whatever a receive or a send raises that is neither
--   `EAGAIN` nor the `EINTR` a stop ends a waiting send with.
-- @usage
--   return tunnel.body(client, upstream, {size = 1024, transform = inspect})
-- @see thread.run
function tunnel.body(a, b, opts)
	opts = opts or {}
	local timeout = opts.timeout or TIMEOUT
	local size = opts.size or SIZE
	-- SO_SNDTIMEO reads a zero as no bound at all and a negative as no wait at all
	assert(timeout > 0, "tunnel: timeout must be positive")
	-- a receive of no bytes answers an empty string, which the relay reads as a close
	assert(size > 0, "tunnel: size must be positive")
	boundsend(a, timeout)
	boundsend(b, timeout)
	local transform = opts.transform
	local forward, backward = newdirection(a, b, transform), newdirection(b, a, transform)
	local idle = opts.idle or IDLE
	return function() run(forward, backward, size, idle) end
end

return tunnel

