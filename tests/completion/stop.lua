--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the completion stop case (see run.sh).

local completion = require("completion")

local TIMEOUT <const> = 10000 -- ms, past the stop run.sh sends

local function body()
	local event = completion.new()
	local ok, err = pcall(event.wait, event, TIMEOUT)
	print("completion stop: " .. (ok and "answered " .. tostring(err) or err))
end

return body

