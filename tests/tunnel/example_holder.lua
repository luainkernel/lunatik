--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The tlstunnel example's own plain port, taken before the example binds it
-- (see example_tunnel.sh).

local common = require("examples.tlstunnel.common")

-- global, so the listener outlives the chunk and the shell releases it by
-- stopping this runtime
listener = common.listener(common.plainport)

