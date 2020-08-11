local lunatik = require'lunatik'
local session = lunatik.session()

-- Normal close
local s1 = session:new's1'
assert(s1 ~= nil)

local err = s1:close()
assert(err ~= nil)
