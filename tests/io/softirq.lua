--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the io softirq guard test (see test.sh).

assert(io == nil, "io must not be available in softirq runtime")
print("io: softirq guard ok")

