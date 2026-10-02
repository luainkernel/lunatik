--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the deferred test, its children whose finalizer sleeps (see deferred.sh).

local deferred = require("tests.runtime.deferred")

local CHILD <const> = "tests/runtime/deferred_sleeper"

deferred.drop(CHILD)

