--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Sender sub-script for the resume_mailbox regression test.
-- Receives a fifo and completion via runtime:resume() and sends a message.

local mailbox = require("mailbox")

local function send(f, c)
	local outbox = mailbox.outbox(f, c)
	outbox:send("hello mailbox!")
end

return send

