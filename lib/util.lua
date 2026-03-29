--- Utility functions.
-- @module util

local util = {}
local char, format, gsub, rep, su = string.char, string.format, string.gsub, string.rep, string.unpack

--- Converts binary string to hex.
-- @function bin2hex
-- @tparam string str Binary string.
-- @treturn string Hexadecimal string.
function util.bin2hex(str)
	return format(rep("%.2x", #str), su(rep("B", #str), str))
end

--- Converts hex string to binary.
-- @function hex2bin
-- @tparam string hex Hexadecimal string.
-- @treturn string Binary string.
function util.hex2bin(hex)
	return gsub(hex, "..", function(cc) return char(tonumber(cc, 16)) end)
end

--- Logs a prefixed message.
-- @function log
-- @tparam string what Prefix (e.g., "info", "error").
-- @tparam ... Message parts (concatenated with tabs).
-- @usage util.log("info", "message")
function util.log(what, ...)
	print(table.concat({what:upper(), ...}, "\t"))
end

--- Runs a test and prints result.
-- @tparam string test_name Test name.
-- @tparam function func Test function.
-- @usage util.test("test", function() ... end)
function util.test(test_name, func)
	local status, err = pcall(func)
	if status then
		util.log("pass", test_name)
	else
		util.log("fail", test_name, err, "\n" .. debug.traceback())
	end
end

return util

