--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Script for the notifier init_dispatch test (see init_dispatch.sh): registers as init_dispatch does, then raises.

require("tests.notifier.init_dispatch")
error("init dispatch: raised", 0)

