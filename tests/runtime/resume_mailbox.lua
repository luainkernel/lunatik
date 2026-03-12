--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the resume_mailbox regression test (see resume_mailbox.sh).
-- Passes a mailbox fifo and completion via runtime:resume() to a sub-runtime
-- that sends a message; the main runtime receives and asserts the value.

local lunatik = require("lunatik")
local mailbox = require("mailbox")

local inbox = mailbox.inbox(64)

local rt = lunatik.runtime("tests/runtime/resume_mailbox_send")
rt:resume(inbox.queue, inbox.event)

local msg = inbox:receive()
assert(msg == "hello mailbox!", msg)

