--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the io interrupt-context guard test (see run.sh).

assert(io == nil, "io must not be available in interrupt-context runtimes")
print("io: interrupt-context guard ok")

