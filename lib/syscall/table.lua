--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- A table mapping system call names to their kernel addresses.
-- This module provides a pre-populated Lua table where each key
-- is a system call name (string, e.g., "openat") and its corresponding
-- value is the kernel address of that system call (lightuserdata).
--
-- @module syscall.table
-- @see syscall
-- @see syscall.numbers
-- @see syscall.address
-- @usage
--   local syscall_addrs = require("syscall.table")
--
--   if syscall_addrs.openat then
--     print("Address of 'openat':", syscall_addrs.openat)
--   end
--
--   if syscall_addrs.close then
--     print("Address of 'close':", syscall_addrs.close)
--   end
--

local syscall = require("syscall")

local table = {}

local numbers = syscall.numbers
for name, number in pairs(numbers) do
	table[name] = syscall.address(number)
end

return table

