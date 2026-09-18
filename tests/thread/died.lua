--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the dying thread body test (see died.sh).

-- level 0 carries no position, which is how a binding re-raises an errno
return function()
	error("EAGAIN", 0)
end

