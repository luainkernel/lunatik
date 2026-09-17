--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the undispatched runtime test (see miss.sh). It attaches no callback:
-- it is run with no execution context, and xdp.attach refuses a process-context runtime.

