--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

-- Cases described in tests/signal/run.sh (signal/mask).

local signal = require("signal")
local sig    = require("linux.signal")

local SIG_UNBLOCK <const> = 1
local HUGE <const> = 1 << 40

signal.sigmask(sig.TERM)
assert(signal.sigstate(sig.TERM) == true, "TERM should be blocked")
assert(signal.sigstate(sig.TERM, "blocked") == true, "TERM should read as blocked")
assert(signal.sigstate(sig.TERM, "allowed") == false, "TERM should not read as allowed")

signal.sigmask(sig.TERM, SIG_UNBLOCK)
assert(signal.sigstate(sig.TERM) == false, "TERM should be unblocked")
assert(signal.sigstate(sig.TERM, "allowed") == true, "TERM should read as allowed")
assert(signal.sigstate(sig.TERM, "pending") == false, "TERM should not be pending")
assert(signal.sigpending() == false, "nothing should be pending")

local function refused(f, ...)
	local ok, err = pcall(f, ...)
	return not ok and err:match("out of bounds") ~= nil, err
end

for _, n in ipairs({0, HUGE}) do
	local ok, err = refused(signal.sigmask, n)
	assert(ok, "sigmask(" .. n .. ") should be out of bounds, got " .. tostring(err))
	ok, err = refused(signal.sigstate, n)
	assert(ok, "sigstate(" .. n .. ") should be out of bounds, got " .. tostring(err))
end
local ok, err = refused(signal.sigmask, sig.TERM, SIG_UNBLOCK + 1)
assert(ok, "a command past SIG_UNBLOCK should be out of bounds, got " .. tostring(err))

