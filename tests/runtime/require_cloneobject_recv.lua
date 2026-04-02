--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Receiver sub-script for the require_cloneobject regression test.
-- Deliberately does NOT require("data") — the class must be loaded by
-- lunatik_cloneobject via lunatik_require (luaL_requiref, no file I/O).
--
-- Clear package.searchers so that require() cannot locate any module.
-- luaL_requiref calls the opener directly and ignores searchers; the
-- broken path (lua_getglobal "require") will fail with "module not found",
-- propagating an error back to the sender and causing the test to fail.
package.searchers = {}

local function recv(d)
	assert(d:getuint32(0) == 0xdeadbeef)
end

return recv

