local lunatik = require'lunatik'
local memory = require'memory'
local session = lunatik.session()

local buffer = memory.create(3)
memory.set(buffer, 1, 0x1, 0x2, 0x3)

local kscript = [[
    function receive_callback(mem)
        print'A memory has been received'
        memory.tostring(mem)
    end
]]

local s1 = session:newstate's1'
assert(s1 ~= nil)

local s2 = session:newstate's2'
assert(s2 ~= nil)

local err = s1:dostring(kscript, 'send script')
assert(err ~= nil)

err = s1:send(buffer)
assert(err ~= nil)

err = s2:send(buffer)
assert(err == nil)

s1:close()
s2:close()
