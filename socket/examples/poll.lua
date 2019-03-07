local server = socket.new("i", "t")
server:bind("0.0.0.0", 8080)
server:listen(5)

-- local client = socket.new("i", "t")
-- client:connect("127.0.0.1", 12345)

local remote = server:accept()

local lpoll = socket.poll({remote})

-- client:send({1, 2, 3})

print("start select")

local index = lpoll:select()

-- when use 'nc' to connect this endpoint and send something, I get "select result: 0"
print("select result: " .. index)
