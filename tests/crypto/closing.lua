--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The close check the crypto class scripts share (see run.sh).

local closing = {}

function closing.check(object, method, ...)
	local class = getmetatable(object)
	assert(class.__close == class.close, class.__name .. "'s __close is not its close")
	object:close()
	object:close()
	local ok, err = pcall(object[method], object, ...)
	assert(not ok and tostring(err):match("closed object"), class.__name .. ":" .. method .. " ran after close")
end

return closing

