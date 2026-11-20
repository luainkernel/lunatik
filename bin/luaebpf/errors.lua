--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Reads back the errors a compiled program counted, from the maps `lunatik run` pinned under its
-- script's root: `luaebpf_errors`, a `u64` per place and CPU, and `luaebpf_errors-lines`, the line
-- of each place, one after another in the order of their entries, each ending in a NUL.
-- @module luaebpf.errors

local loader = require("luaebpf.loader")
local emit   = require("luaebpf.emit")
local proto  = require("luaebpf.proto")

local COUNTS <const> = "%s/" .. emit.ERRORS
local LINES  <const> = COUNTS .. "-lines" -- the name luaebpf.loader pins the map of the lines under
local PLACE  <const> = "^(.*):(%d+): (.*)$" -- no reason the compiler writes holds a colon, digits and ": "

local errors = {}

-- whether the root pins no map to count in, as an object whose program stops nowhere declares none
local function absent(counts)
	-- read here, not as the module loads: a compile loads it too, and may have no /lib/modules/lua
	return select(3, loader.lookup(counts, 0)) == proto.script("linux.errno").ENOENT
end

-- the line of each place, in the order of their entries
local function lines(path)
	local bytes, err = loader.lookup(path, 0)
	if bytes == nil then
		return nil, err
	end
	local found = {}
	for line in bytes:gmatch("([^\0]*)\0") do
		table.insert(found, line)
	end
	return found
end

-- the count of the place at the index, summed over the entries of the CPUs
local function count(counts, index)
	local values, err = loader.lookup(counts, index)
	if values == nil then
		return nil, err
	end
	local sum = 0
	for _, value in ipairs(values) do
		sum = sum + string.unpack("I8", value)
	end
	return sum
end

-- a place's line, `<file>:<line>: <reason>`, as the table the report reads
local function place(line, n)
	local file, number, reason = line:match(PLACE)
	return {file = file, line = math.tointeger(number), reason = reason, count = n}
end

---
-- Reads back the errors of the program whose maps are pinned under `root`, as `luaebpf.errors`.
-- @function luaebpf.errors.read
-- @tparam string root the directory `lunatik run` pinned the program's maps in
-- @treturn table|nil a table per place, `{file, line, reason, count}`, in the order of their entries
-- @treturn string the message, where a pin cannot be read
function errors.read(root)
	local counts = COUNTS:format(root)
	if absent(counts) then
		return {}
	end
	local found, err = lines(LINES:format(root))
	if found == nil then
		return nil, err
	end
	local places = {}
	for index, line in ipairs(found) do
		local n, failed = count(counts, index - 1)
		if n == nil then
			return nil, failed
		end
		table.insert(places, place(line, n))
	end
	return places
end

return errors

