--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for fifo/close (see run.sh).

local fifo = require("fifo")

local CAPACITY <const> = 16
local BYTE     <const> = "x"

local function close(queue)
	local own <close> = fifo.new(CAPACITY)
	own:push(BYTE)
	assert(own:pop(#BYTE) == BYTE, "the fifo created past the body lost its byte")
	queue:close()
end

return close

