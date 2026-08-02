--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- High-level view over pinned eBPF maps.
-- Each constructor mirrors the one in `bpf`, taking the packing spec of what
-- the map holds. Key-value maps become table proxies: indexing looks values
-- up, assignment updates, assigning `nil` deletes, and `pairs` iterates.
-- Keyless maps become objects, with `push`, `pop` and `peek`.
--
-- Keys and values are opaque fixed-size buffers to eBPF. A spec is either a
-- `string.pack` format (e.g. `"I4"`, `"c6"`) or a `struct` codec, and says both
-- how many bytes it takes, validated against the map on open, and how to read
-- them. Specs that pack a single value take and return it as a scalar;
-- multi-value formats and `struct` codecs take and return an array of values,
-- in field order.
--
-- Operations on a table proxy come from outside it (`close` and `info` are
-- module functions, as in Lua's `table` library or `rcu.map`), so any key the
-- spec can encode is a valid map key.
--
-- Conditional updates (`BPF_NOEXIST`/`BPF_EXIST`) and the boolean results
-- belong to the raw API.
-- @module bpf.map
-- @see bpf
-- @usage
-- local map = require("bpf.map")
--
-- local counters <close> = map.hash("/sys/fs/bpf/counters", "I4", "I4")
-- counters[1] = 42
-- print(counters[1])
-- counters[1] = nil                 -- delete
-- for key, value in pairs(counters) do print(key, value) end
--
-- local events <close> = map.queue("/sys/fs/bpf/events", "I8")
-- events:push(1234)
-- print(events:pop())

local bpf   = require("bpf")
local class = require("class")

local pack, unpack, packsize = string.pack, string.unpack, string.packsize
local tabunpack              = table.unpack

local function collect(...)
	local values = {...}
	values[#values] = nil
	return values
end

local scalar = class{}

function scalar:encode(value)
	return pack(self.format, value)
end

function scalar:decode(buffer)
	return (unpack(self.format, buffer))
end

local array = class{}

function array:encode(values)
	return pack(self.format, tabunpack(values))
end

function array:decode(buffer)
	return collect(unpack(self.format, buffer))
end

local record = class{}

function record:encode(values)
	return self.struct:pack(tabunpack(values))
end

function record:decode(buffer)
	return collect(self.struct:unpack(buffer))
end

local function isscalar(format, size)
	return select("#", unpack(format, ("\0"):rep(size))) == 2
end

local codecs = {}

function codecs.string(format)
	local size = packsize(format)
	local codec = isscalar(format, size) and scalar or array
	return codec:new{format = format, size = size}
end

function codecs.table(struct)
	if struct.pack == nil or struct.size == nil then
		return nil
	end
	return record:new{struct = struct, size = struct.size}
end

local function newcodec(spec, what, expected)
	local new = codecs[type(spec)]
	local codec = new and new(spec)
	if codec == nil then
		error("invalid " .. what .. " spec")
	end
	if codec.size ~= expected then
		error(("%s spec packs %d bytes, map expects %d"):format(what, codec.size, expected))
	end
	return codec
end

local function decode(codec, raw)
	if raw == nil then
		return nil
	end
	return codec:decode(raw)
end

local map_queue = class{}

local states = setmetatable({}, {__mode = "k"})

local map = {}

local function iterate(proxy, key)
	local state = states[proxy]
	local rawkey = state.map:next(key ~= nil and state.key:encode(key) or nil)
	if rawkey == nil then
		return nil
	end
	return state.key:decode(rawkey), decode(state.value, state.map:lookup(rawkey))
end

---
-- Releases the map reference.
-- Also wired as the proxy's `__close` metamethod.
-- @function close
-- @tparam map_hash proxy the table proxy
function map.close(proxy)
	states[proxy].map:close()
end

---
-- Returns the map properties, as `bpf` map `info`.
-- @function info
-- @tparam map_hash proxy the table proxy
-- @treturn table `type`, `key_size`, `value_size` and `max_entries`
function map.info(proxy)
	return states[proxy].map:info()
end

local view = {__close = map.close}

function view.__index(proxy, key)
	local state = states[proxy]
	return decode(state.value, state.map:lookup(state.key:encode(key)))
end

function view.__newindex(proxy, key, value)
	local state = states[proxy]
	local rawkey = state.key:encode(key)
	if value == nil then
		state.map:delete(rawkey)
	else
		state.map:update(rawkey, state.value:encode(value))
	end
end

function view.__pairs(proxy)
	return iterate, proxy, nil
end

local function openproxy(open, pathname, keyspec, valuespec)
	local handle = open(pathname)
	local info = handle:info()
	local proxy = setmetatable({}, view)
	states[proxy] = {
		map = handle,
		key = newcodec(keyspec, "key", info.key_size),
		value = newcodec(valuespec, "value", info.value_size),
	}
	return proxy
end

local function openqueue(open, pathname, valuespec)
	local handle = open(pathname)
	local info = handle:info()
	return map_queue:new{map = handle, value = newcodec(valuespec, "value", info.value_size)}
end

---
-- Opens a pinned hash map as a table.
-- @function hash
-- @tparam string pathname Path to the pinned map.
-- @tparam string|table keyspec `string.pack` format or `struct` codec for the key.
-- @tparam string|table valuespec `string.pack` format or `struct` codec for the value.
-- @treturn map_hash the table proxy
-- @raise Error if the map cannot be opened or a spec does not match its sizes.
function map.hash(pathname, keyspec, valuespec)
	return openproxy(bpf.hash, pathname, keyspec, valuespec)
end

---
-- Opens a pinned array map as a table.
-- Keys are the `u32` indices of the array.
-- @function array
-- @tparam string pathname Path to the pinned map.
-- @tparam string|table keyspec `string.pack` format or `struct` codec for the key.
-- @tparam string|table valuespec `string.pack` format or `struct` codec for the value.
-- @treturn map_hash the table proxy
-- @raise Error if the map cannot be opened or a spec does not match its sizes.
function map.array(pathname, keyspec, valuespec)
	return openproxy(bpf.array, pathname, keyspec, valuespec)
end

---
-- Opens a pinned LRU hash map as a table.
-- @function lru_hash
-- @tparam string pathname Path to the pinned map.
-- @tparam string|table keyspec `string.pack` format or `struct` codec for the key.
-- @tparam string|table valuespec `string.pack` format or `struct` codec for the value.
-- @treturn map_hash the table proxy
-- @raise Error if the map cannot be opened or a spec does not match its sizes.
function map.lru_hash(pathname, keyspec, valuespec)
	return openproxy(bpf.lru_hash, pathname, keyspec, valuespec)
end

---
-- Opens a pinned queue map (FIFO).
-- @function queue
-- @tparam string pathname Path to the pinned map.
-- @tparam string|table valuespec `string.pack` format or `struct` codec for the value.
-- @treturn map_queue the map object
-- @raise Error if the map cannot be opened or the spec does not match its value size.
function map.queue(pathname, valuespec)
	return openqueue(bpf.queue, pathname, valuespec)
end

---
-- Opens a pinned stack map (LIFO).
-- @function stack
-- @tparam string pathname Path to the pinned map.
-- @tparam string|table valuespec `string.pack` format or `struct` codec for the value.
-- @treturn map_queue the map object
-- @raise Error if the map cannot be opened or the spec does not match its value size.
function map.stack(pathname, valuespec)
	return openqueue(bpf.stack, pathname, valuespec)
end

---
-- Table view over a key-value map, as returned by `hash`, `array` and
-- `lru_hash`. It has no methods, so any key the spec can encode is a valid
-- map key: indexing looks values up, assignment updates, assigning `nil`
-- deletes, `pairs` iterates, and closing the variable (`<close>`) releases
-- the map. `close` and `info` are module functions.
-- @type map_hash

---
-- Keyless map object, as returned by `queue` and `stack`.
-- @type map_queue

---
-- Inserts a value.
-- @function map_queue:push
-- @param value the value to insert, as the spec encodes it
-- @treturn boolean `false` if the map is full, `true` otherwise
-- @raise Error if the operation fails.
function map_queue:push(value)
	return self.map:push(self.value:encode(value))
end

---
-- Removes and returns the next value.
-- @function map_queue:pop
-- @return the value, or `nil` if the map is empty
-- @raise Error if the operation fails.
function map_queue:pop()
	return decode(self.value, self.map:pop())
end

---
-- Returns the next value, leaving it in the map.
-- @function map_queue:peek
-- @return the value, or `nil` if the map is empty
-- @raise Error if the operation fails.
function map_queue:peek()
	return decode(self.value, self.map:peek())
end

---
-- Returns the map properties, as `bpf` map `info`.
-- @function map_queue:info
-- @treturn table `type`, `key_size`, `value_size` and `max_entries`
function map_queue:info()
	return self.map:info()
end

---
-- Releases the map reference.
-- Also wired as the object's `__close` metamethod.
-- @function map_queue:close
function map_queue:close()
	self.map:close()
end

return map

