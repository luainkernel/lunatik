--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the luac test (see run.sh): a library installed as a compiled chunk.

local lib = {}

function lib.answer()
	return 42
end

return lib

