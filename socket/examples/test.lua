assert(socket)
sock1 = socket.new("i", "t")
assert(sock1)

sock1:bind("127.0.0.1", 80)
sock1:listen(5)

sock2 = socket.new("i", "t")
assert(sock2)

sock2:connect("127.0.0.1", 80)
sock3 = sock1:accept()
assert(sock3)

sock3:sendmsg({}, {1, 2, 3})
local d, size, header = sock2:recvmsg({iov_len = 5})
assert(#d == 3)
assert(size == 3)
print(header.iov_len)
print(header.name.port)

sock4 = socket.new("i", "u")
assert(sock4)
sock4:sendmsg(
    {
        name = {
            addr = "127.0.0.1",
            port = 1234
        }
    },
    {1, 2, 3}
)
d1 = data.new {0xFF, 0xFE, 0x00}

sock3:sendmsg({}, d1)
d2 = data.new(3)
sock2:recvmsg({}, d2)
assert(d1[1] == d2[1])
assert(d1[2] == d2[2])
assert(d1[3] == d2[3])

addr, port = sock2:getsockname()
print(addr)
print(port)
addr, port = sock2:getpeername()
print(addr)
print(port)

print(sock2:getsockopt("s", "r"))

sock5 = socket.new("i", "t")
sock5:bind(0x7f000001, 7777)
addr, port = sock5:getsockname()
print(addr)
assert(addr == "127.0.0.1")

sock1:close()
sock2:close()
sock3:close()
sock4:close()
sock5:close()

print("closed all sockets")
