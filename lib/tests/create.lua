local lunatik = require'lunatik'
local session = lunatik.session()

-- Normal creation
local s1 = session:newstate's1'
assert(s1)
assert(s1:getname() == 's1')
assert(s1:getmaxalloc() == lunatik.defaultmaxallocbytes)
-- assert(s1:getcurralloc() ~= nil)

-- Max alloc greater than MIN_ALLOC
local s2 = session:newstate('s2', 100000)
assert(s2)

-- Max alloc less than MIN_ALLOC
local s3 = session:newstate('s3', 1)
assert(s3 == nil)

-- State already exists
local s4 = session:newstate's1'
assert(s4 == nil)

-- State creation from another session
local session2 = lunatik.session()

-- Normal creation
ss1 = session2:newstate'ss1'
assert(ss1)

-- State created from another session
ss2 = session2:newstate's1'
assert(ss2 == nil)

s1:close()
s2:close()
ss1:close()
session:close()
session2:close()
