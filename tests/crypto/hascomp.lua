--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Raises where the crypto module has no comp; run.sh matches this message.

assert(require("crypto").comp, "crypto.comp is not built")

