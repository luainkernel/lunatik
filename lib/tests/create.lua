local lunatik = require'lunatik'

local session = lunatik.session()

-- Normal creation
local s1 = session:new's1'
assert(s1 ~= nil)

-- Max alloc greater than MIN_ALLOC
local s2 = session:new('s2', 100000)
assert(s2 ~= nil)

-- Max alloc less than MIN_ALLOC
local s3 = session:new('s3', 1)
assert(s3 == nil)

-- State already exists
local s4 = session:new's1'
assert(s4 == nil)

-- State creation from another session
local session2 = lunatik.session()

-- Normal creation
ss1 = session2:new'ss1'
assert(ss1 ~= nil)

-- State created from another session
ss2 = session2:new's1'
assert(ss2 == nil)


s1:close()
s2:close()
ss1:close()
session:close()
session2:close()
