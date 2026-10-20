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

local unpack = table.unpack

local VERDICT <const> = 0xffffffff -- the 32 bits bpf_prog_run returns
local ORACLE  <const> = "oracle.txt"

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

function corpus.new()
	return rows:new{out = assert(io.open(ORACLE, "w"))}
end

function rows:declare(name, fn, default)
	local program = xdp.program(fn, {name = name, default = default})
	self.out:write(name, "\t", answer(pcall(fn, 0)), "\t", program.default, "\n")
end

function rows:close()
	self.out:close()
end

-- a row per maker in order and argument list in operands, named after the maker and the list's place
function corpus.declare(makers, order, operands, default)
	local declared = corpus.new()
	for _, op in ipairs(order) do
		for i, args in ipairs(operands) do
			declared:declare(op .. i, makers[op](unpack(args)), default)
		end
	end
	declared:close()
end

return corpus

