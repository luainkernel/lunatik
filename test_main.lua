local linux = require("linux")
local device = require("device")

local function nop() end

local s = linux.stat
local testmain = {
    name = "lunatiktest",
    open = nop,
    release = nop,
    mode = s.IRUGO
}

function testmain:read()
    local realtime = linux.time()
    local monotonic = linux.monotonic()
    local boottime = linux.boottime()
    local clocktai = linux.clocktai()
    local rawtime = linux.rawtime()
    return string.format([[
        realtime: %d,
        monotonic: %d, 
        boottime: %d,
        clocktai: %d,
        rawtime: %d,
    ]], realtime, monotonic, boottime, clocktai, rawtime)
end

device.new(testmain)
