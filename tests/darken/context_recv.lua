--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the darken context test (see run.sh).

local darken  = require("darken")
local hex2bin = require("util").hex2bin

local KEY        <const> = string.rep("k", 32)
local IV         <const> = string.rep("i", 16)
local CIPHERTEXT <const> = hex2bin("68d45694715e8b1762") -- "return 42" under KEY and IV, openssl's aes-256-ctr
local ANSWER     <const> = 42

local function run()
	assert(darken.run(CIPHERTEXT, IV, KEY) == ANSWER, "darken.run did not run the chunk")
end

run()

return run

