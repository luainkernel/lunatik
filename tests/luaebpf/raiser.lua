--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the loader undo test (see undo.sh): its body raises, so the run has a
-- loaded object and an attach still to come when the runtime fails.

error("luaebpf raiser raised on purpose", 0)

