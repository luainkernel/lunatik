--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Userspace writer of the files set.load reads, for the set suite (see run.sh): lua5.5 write.lua <list> <file>

local MAGIC      <const> = "LSET"
local VERSION    <const> = 1
local LABELED    <const> = 1
local UINT32_MAX <const> = 0xffffffff

local function read_label(word, where)
	local label = word:match("^%d+$") and math.tointeger(tonumber(word))
	if not label or label < 1 or label > UINT32_MAX then
		error(where .. "labels must be integers in [1, 2^32)", 0)
	end
	return label
end

-- a line holds a member, then whitespace and its label in a map; a blank line holds none
local function read_line(line, where)
	if not line:find("%S") then
		return nil
	end
	local member, word = line:match("^%s*(%S+)%s*(%S*)%s*$")
	if member == nil then
		error(where .. "more than a member and a label", 0)
	end
	return member, word ~= "" and read_label(word, where) or nil
end

local function add_member(set, member, label, where)
	local labeled = label ~= nil
	if set.labeled ~= nil and set.labeled ~= labeled then
		error(where .. "a list and a map mixed", 0)
	end
	set.labeled = labeled
	if set.labels[member] == nil then
		table.insert(set.members, member)
		set.labels[member] = label or 1
	elseif labeled then
		error(where .. "a member listed twice in a map", 0)
	end
end

local function read_list(list)
	local input <close>, err = io.open(list)
	if input == nil then
		error(err, 0)
	end
	local set = {members = {}, labels = {}}
	local number = 0
	for line in input:lines() do
		number = number + 1
		local where = string.format("%s:%d: ", list, number)
		local member, label = read_line(line, where)
		if member ~= nil then
			add_member(set, member, label, where)
		end
	end
	table.sort(set.members) -- set.load reads this order: < in the C locale compares bytes, the shorter first on a tie
	return set
end

local function pack_set(set)
	local offsets, labels = {string.pack("<I4", 0)}, {}
	local len = 0
	for _, member in ipairs(set.members) do
		len = len + #member
		if len > UINT32_MAX then
			error("members exceed 4 GiB", 0)
		end
		table.insert(offsets, string.pack("<I4", len))
		table.insert(labels, string.pack("<I4", set.labels[member]))
	end
	local flags = set.labeled and LABELED or 0
	return string.pack("<c4I2I2I4I4", MAGIC, VERSION, flags, #set.members, len),
		table.concat(offsets), set.labeled and table.concat(labels) or "", table.concat(set.members)
end

local list, file = arg[1], arg[2]
local set = read_list(list)
local output <close> = assert(io.open(file, "wb"))
assert(output:write(pack_set(set)))

