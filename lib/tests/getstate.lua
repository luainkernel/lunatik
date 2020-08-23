local lunatik = require'lunatik'
local memory = require'memory'
local buffer = memory.create(3)
local session = lunatik.session()

local kscript = [[
    print'olá mundo!'
]]

-- Testing state normal state creation
local s1 = session:newstate's1'
assert(s1 ~= nil)
local err = s1:dostring(kscript)
assert(err ~= nil)

-- Trying to get a state created on user space
local state = session:getstate's1'
assert(state == nil)

-- Try to get a state nonexistent state
local state2 = session:getstate's4'
assert(state2 == nil)

s1:close()

session:close()
