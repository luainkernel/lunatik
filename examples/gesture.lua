local hid = require("hid")
local data = require("data")

local driver = {
  name = "gesture",
  id_table = {
    { vendor = 0x0627, product = 0x0001 }
  }
}

function driver:probe(devid)
  return { x = 0, y = 0, drag = false}
end

function driver:raw_event(hdev, state, report, raw_data)
  local btn = raw_data:getbyte(0)
  local dx_byte = raw_data:getbyte(1)
  local dy_byte = raw_data:getbyte(2)
  -- complement conversion
  local dx = dx_byte >= 128 and dx_byte - 256 or dx_byte
  local dy = dy_byte >= 128 and dy_byte - 256 or dy_byte

  local left_down = (btn & 1) == 1
  if left_down then
    state.drag = true
    state.x = state.x + dx
    state.y = state.y + dy
  else
    if state.drag then
      if math.abs(state.x) > 100 or math.abs(state.y) > 100 then
        direction = ""
        if math.abs(state.x) > math.abs(state.y) then
          direction = state.x > 0 and "rightly" or "leftly"
        else
          direction = state.y > 0 and "downly" or "uply"
        end
        print(string.format("Swipe %s with x=%d, y=%d", direction, state.x, state.y))
      end
      state.x = 0
      state.y = 0
      state.drag = false
    end
  end
  return false
end

hid.register(driver)
