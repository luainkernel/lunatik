local lunatik = require'lunatik'
local session = lunatik.session()
local session2 = lunatik.session()

-- Create states that will be present on the list
local s1 = session:newstate's1'
local s2 = session:newstate's2'
local s3 = session:newstate('s3', 100000)

local ss1 = session2:newstate'ss1'
local ss2 = session2:newstate'ss2'
local ss3 = session2:newstate('ss3', 100000)

-- Create states that are not be present on the list
session:newstate('s4', 1)
session2:newstate('ss4', 1)

-- Get the states information from kernel
local states = session:list()
local states2 = session2:list()

assert(#states == 6)
assert(#states2 == 6)


-- Close some states and check if they are gone when list
s1:close()
s2:close()
s3:close()

states = session:list()
states2 = session2:list()

assert(#states == 3)
assert(#states2 == 3)

ss1:close()
ss2:close()
ss3:close()
