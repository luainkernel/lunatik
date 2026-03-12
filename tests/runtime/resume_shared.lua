--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the resume_shared regression test (see resume_shared.sh).
-- Passes a shared (monitored) fifo object via runtime:resume().

local lunatik = require("lunatik")
local fifo    = require("fifo")

local rt = lunatik.runtime("tests/runtime/resume_shared_recv")
local f  = fifo.new(13)
f:push("hello kernel!")
rt:resume(f)

