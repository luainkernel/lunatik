--
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- A table mapping system call names to their kernel addresses.
-- This module provides a pre-populated Lua table where each key
-- is a system call name (string, e.g., "openat") and its corresponding
-- value is the kernel address of that system call (lightuserdata).
-- A name `linux.syscall.numbers` does not carry is `nil`, as `open` is on arm64.
--
-- @module syscall.table
-- @see syscall
-- @see linux.syscall.numbers
-- @see syscall.address
-- @usage
--   local syscall_addrs = require("syscall.table")
--
--   print("Address of 'openat':", syscall_addrs.openat)
--
--   if syscall_addrs.open then
--     print("Address of 'open':", syscall_addrs.open)
--   end
--

local syscall = require("syscall")
local numbers = require("linux.syscall").numbers

local table = {}

for name, number in pairs(numbers) do
	table[name] = syscall.address(number)
end

return table

