--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The rows a corpus case's program file declares (see common.sh): each is handed to
-- xdp.program, and what the CLI's Lua answers for it is written beside the object, which the
-- case compares against what the compiled program returns. A program file's body requires it,
-- so it installs with the kernel scripts and loads through lunatic, which makes that answer the
-- one the kernel computes; nothing runs it in the kernel.

local class = require("class")
local xdp   = require("bpf.xdp")

local VERDICT <const> = 0xffffffff -- the 32 bits bpf_prog_run returns

local corpus = {}

local rows = class{}

local function answer(ok, value)
	if not ok then
		return "raises"
	end
	if type(value) == "boolean" then
		return value and "1" or "0"
	end
	return tostring(value & VERDICT)
end

function corpus.new(path)
	return rows:new{out = assert(io.open(path or "oracle.txt", "w"))}
end

function rows:declare(name, fn, opts)
	opts = opts or {}
	opts.name = name
	xdp.program(fn, opts)
	self.out:write(name, "\t", answer(pcall(fn, 0)), "\n")
end

function rows:close()
	self.out:close()
end

return corpus

