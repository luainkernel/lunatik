--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the scx pass test (see run.sh).

local scx = require("scx")
local ext = require("linux.scx")

local DSQ_DEFAULT <const> = 0
local SLICE       <const> = 5000000 -- apart from the slices linux.scx names

-- the answer to each task run.sh starts, by the comm it names it with
local cells = {}

function cells.scx_none()
end

function cells.scx_raise()
	error("scx pass: raised", 0)
end

function cells.scx_nil_dsq()
	return nil, SLICE
end

function cells.scx_nil_slice()
	return ext.dsq.LOCAL, nil
end

function cells.scx_str_dsq()
	return tostring(ext.dsq.GLOBAL), SLICE
end

function cells.scx_bool_slice()
	return ext.dsq.GLOBAL, true
end

function cells.scx_local()
	return ext.dsq.LOCAL, ext.slice.INF
end

function cells.scx_global()
	return ext.dsq.GLOBAL, SLICE
end

function cells.scx_local_on(task)
	return ext.dsq.LOCAL_ON | task:cpu(), ext.slice.INF
end

function cells.scx_detach()
	scx.detach()
	return ext.dsq.GLOBAL, SLICE
end

local function workload(ctx)
	local task = ctx:task()
	local cell = cells[task:comm()]
	if cell then
		return cell(task)
	end
	return DSQ_DEFAULT, ext.slice.DFL
end

scx.attach(workload)

