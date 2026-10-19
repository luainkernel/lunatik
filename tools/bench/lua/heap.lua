--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

collectgarbage()
local heap = collectgarbage("count") -- bytes in the kernel, LUNATIK_GCCOUNT
print(string.format("bench %s heap %d", require("bench.params").nonce, heap))

