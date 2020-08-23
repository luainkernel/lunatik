local lunatik = require'lunatik'
local session = lunatik.session()

-- Normal close
local s1 = session:new's1'
assert(s1 ~= nil)

local err = s1:close()
assert(err ~= nil)

-- Using state after close session
s1 = session:new's1'
assert(s1 ~= nil)

session:close()
assert(s1:getname() == 's1')

err = s1:close()
assert(err)

-- Trying to close nonexistent state
err = s1:close()
assert(err == nil)
