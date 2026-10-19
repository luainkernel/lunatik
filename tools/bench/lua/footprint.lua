--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local names  = require("bench.names")
local params = require("bench.params")

-- a global, so the runtimes live until the script is stopped
runtimes = {}
for i = 1, params.n do
	runtimes[i] = names.runtime(params.script, params.context)
end
print(string.format("bench %s ready", params.nonce))

