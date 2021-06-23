local lunatik = require'lunatik'

local session = lunatik.session()
local session2 = lunatik.session()

session:close()
session2:close()
