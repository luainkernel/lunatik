--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- A device of another runtime for the self_stop test (see self_stop.sh).

local device = require("device")

local NAME <const> = "lunatik_self_stop_other"

device.new{name = NAME}

