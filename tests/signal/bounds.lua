--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The bound check the signal scripts share (see run.sh).

local bounds = {}

function bounds.refused(f, ...)
	local ok, err = pcall(f, ...)
	return not ok and err:match("out of bounds") ~= nil, err
end

return bounds

