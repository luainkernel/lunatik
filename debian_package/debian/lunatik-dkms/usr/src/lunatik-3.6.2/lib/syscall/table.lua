--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local syscall = require("syscall")

local table = {}

local numbers = syscall.numbers
for name, number in pairs(numbers) do
	table[name] = syscall.address(number)
end

return table

