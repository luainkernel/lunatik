local lunatik = require'lunatik'
local memory = require'memory'
local buffer = memory.create(3)
local session = lunatik.session()

local kscript = [[
    print'olá mundo!'
]]

local s1 = session:new's1'
assert(s1 ~= nil)
local err = s1:dostring(kscript)
assert(err ~= nil)

local state = session:getstate's1'
assert(state ~= nil)
err = state:dostring(kscript)
assert(err ~= nil)

local state2 = session:getstate's4'
assert(state2 == nil)

s1:close()
state:close()

session:close()
