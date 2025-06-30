--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require("lunatik")
local mailbox = require("mailbox")
local fifo = require("fifo")
local completion = require("completion")

local function assert_true(condition, message)
	if not condition then
		error("Assertion failed: " .. (message or "Expected true"))
	end
end

local function assert_equal(expected, actual, message)
	if expected ~= actual then
		error("Assertion failed: " .. (message or "") .. " Expected '" .. tostring(expected) .. "', got '" .. tostring(actual) .. "'")
	end
end

local function assert_is_nil(value, message)
	if value ~= nil then
		error("Assertion failed: " .. (message or "") .. " Expected nil, got '" .. tostring(value) .. "'")
	end
end

local function assert_has_error(func, expected_error_msg)
	local ok, err = pcall(func)
	assert_true(not ok, "Assertion failed: Expected an error, but no error occurred.")
	if expected_error_msg then
		assert_true(string.find(err, expected_error_msg), "Assertion failed: Expected error message containing '" .. expected_error_msg .. "', but got '" .. err .. "'")
	end
end

local MailboxTests = {}

function MailboxTests.test_local_inbox_outbox()
	local outbox = mailbox.outbox(1024)
	local inbox = mailbox.inbox(outbox.queue, outbox.event)

	assert_true(pcall(outbox.send, outbox, "hello"))
	assert_equal("hello", inbox:receive(0))

	assert_is_nil(inbox:receive(0)) -- Should be empty now

	-- Test send on inbox (should error)
	assert_has_error(function() inbox:send("should fail") end, "receive%-only mailbox")

	-- Test receive on outbox (should error)
	assert_has_error(function() outbox:receive(0) end, "send%-only mailbox")
end

function MailboxTests.test_non_blocking_mailbox()
	local outbox = mailbox.outbox(false) -- Non-blocking outbox
	local inbox = mailbox.inbox(outbox.queue, false) -- Non-blocking inbox

	assert_true(pcall(outbox.send, outbox, "non-blocking message"))
	assert_equal("non-blocking message", inbox:receive(0))
	assert_is_nil(inbox:receive(0))

	-- Test non-blocking receive on empty mailbox
	local empty_inbox = mailbox.inbox(1, false)
	assert_is_nil(empty_inbox:receive(0))
end

function MailboxTests.test_rcu_mailbox()
	local mbox_name = "test_rcu_mailbox_name"

	-- Ensure _ENV is clean before test
	lunatik._ENV[mbox_name] = nil

	local outbox1 = mailbox.outbox(mbox_name)
	local inbox1 = mailbox.inbox(mbox_name)

	assert_true(pcall(outbox1.send, outbox1, "rcu message 1"))
	assert_equal("rcu message 1", inbox1:receive(0))

	-- Create new instances, they should share the same underlying queue
	local outbox2 = mailbox.outbox(mbox_name)
	local inbox2 = mailbox.inbox(mbox_name)

	assert_true(pcall(outbox2.send, outbox2, "rcu message 2"))
	assert_equal("rcu message 2", inbox2:receive(0))

	-- Test that the queue is indeed shared
	assert_equal(outbox1.queue, outbox2.queue)
	assert_equal(inbox1.queue, inbox2.queue)
	assert_equal(outbox1.queue, inbox1.queue)

	-- Test RCU update mechanism (simulated by re-assigning _ENV[mbox_name])
	local new_fifo = fifo.new(10)
	lunatik._ENV[mbox_name] = new_fifo

	local outbox3 = mailbox.outbox(mbox_name)
	local inbox3 = mailbox.inbox(mbox_name)

	assert_true(pcall(outbox3.send, outbox3, "rcu message 3"))
	assert_equal("rcu message 3", inbox3:receive(0))

	assert_equal(outbox3.queue, new_fifo)
	assert_equal(inbox3.queue, new_fifo)

	-- Old mailboxes should now point to the new queue after their next operation
	outbox1:send("rcu message 4")
	assert_equal(outbox1.queue, new_fifo)
	assert_equal("rcu message 4", inbox3:receive(0))

	inbox1:receive(0) -- This will update inbox1.queue
	assert_equal(inbox1.queue, new_fifo)

	-- Clean up _ENV
	lunatik._ENV[mbox_name] = nil
end

function MailboxTests.test_mailbox_capacity()
	local outbox = mailbox.outbox(1) -- Capacity of 1 message
	local inbox = mailbox.inbox(outbox.queue, outbox.event)

	assert_true(pcall(outbox.send, outbox, "message 1"))
	assert_has_error(function() outbox:send("message 2") end, "fifo is full")

	assert_equal("message 1", inbox:receive(0))
	assert_is_nil(inbox:receive(0))

	assert_true(pcall(outbox.send, outbox, "message 3"))
	assert_equal("message 3", inbox:receive(0))
end

function MailboxTests.test_receive_timeout()
	local outbox = mailbox.outbox(1)
	local inbox = mailbox.inbox(outbox.queue, outbox.event)

	-- Test immediate return (timeout 0)
	local msg = inbox:receive(0)
	assert_is_nil(msg)

	-- Test blocking receive with timeout (short timeout, should return nil)
	msg = inbox:receive(1) -- 1 jiffy timeout
	assert_is_nil(msg)

	-- Test blocking receive with message (should return message)
	outbox:send("timed message")
	msg = inbox:receive(100) -- Long timeout, but message is there
	assert_equal("timed message", msg)
end

function MailboxTests.test_malformed_message()
	local outbox = mailbox.outbox(1)
	local inbox = mailbox.inbox(outbox.queue, outbox.event)

	-- Manually push a malformed header to the queue
	outbox.queue:push("short") -- Not enough bytes for string.unpack("T")

	assert_has_error(function() inbox:receive() end, "malformed message")
end

local function run_tests()
	local num_passed = 0
	local num_failed = 0

	print("\nRunning Mailbox Tests...")

	for name, func in pairs(MailboxTests) do
			print("  " .. name .. ": ")
			local ok, err = pcall(func)
			if ok then
				print("PASS")
				num_passed = num_passed + 1
			else
				print("FAIL - " .. err)
				num_failed = num_failed + 1
			end
	end

	print(string.format("\nTests finished: %d passed, %d failed", num_passed, num_failed))
	if num_failed > 0 then
		error("Some tests failed.")
	end
end

run_tests()

