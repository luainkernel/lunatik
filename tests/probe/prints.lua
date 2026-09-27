--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The handlers the probe handlers scripts register, each printing the line handlers.sh counts.

local prints = {}

function prints.pre()
	print("probe handlers: pre")
end

function prints.post()
	print("probe handlers: post")
end

return prints

