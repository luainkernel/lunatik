local lunatik = require'lunatik'
local memory = require'memory'
local session = lunatik.session()

local kscript = [[
    local buffer = memory.create(3)
    memory.set(buffer, 1, 65, 66, 67)
    netlink.send(buffer)
    memory.set(buffer, 1, 68, 69, 70)
    netlink.send(buffer)
]]

local s1 = session:newstate's1'
assert(s1 ~= nil)

local err = s1:dostring(kscript, 'receive')
assert(err ~= nil)

local buffer = s1:receive()
assert(memory.tostring(buffer) == 'ABC')

buffer = s1:receive()
assert(memory.tostring(buffer) == 'DEF')

s1:close()
