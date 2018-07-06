local PORT = 8080

Client = {}
Head =
    data.layout {
    vn = {0, 8},
    cd = {8, 8},
    dstport = {16, 16, "number", "net"},
    dstip = {32, 32, "number", "net"}
}
Command = {
    connect = 1,
    bind = 2,
    granted = 90,
    rejected = 91
}
local REQUEST_MIN = 9
local REPONSE_SIZE = 8

function Client:new(socket, buf_size)
    o = {}
    setmetatable(o, {__index = self})
    self.socket = socket
    self.buf = data.new(buf_size or 1024)
    self.addr, self.port = socket:getpeername()
    return o
end

function Client:handle()
    assert(self.socket ~= nil)
    print("start handle " .. self.addr .. ":" .. self.port)
    local _, size = self.socket:recv(self.buf)

    assert(size > REQUEST_MIN)
    print("received size: " .. size)

    local req_size = nil
    for i = REQUEST_MIN, size do
        local char = self.buf:layout({c = {(i - 1) * 8, 8}}).c
        if (char == 0) then
            req_size = i
            print("request size: " .. i)
            break
        end
    end
    -- only support SOCKS4 and CONNECT command now
    local req = self.buf:layout(Head)
    if req.vn ~= 4 or req.cd ~= Command.connect then
        print("Not SOCKS4 or not connect")
        print("version: " .. req.vn .. " command: " .. req.cd)
        self:response(Command.rejected, req.dstport, req.dstip)
        self.socket:close()

        return
    end

    print("try establish connection to " .. req.dstip .. ":" .. req.dstport)
    local sock = socket.new("i", "t")
    local state, err = pcall(sock.connect, sock, req.dstip, req.dstport)
    if not state then
        print("connect failed: " .. err)
        self:response(Command.rejected, req.dstport, req.dstip)
        self.socket:close()

        return
    end

    print("establish connection ok")
    self:response(Command.granted, req.dstport, req.dstip)
    self.target_socket = sock
    pcall(
        -- only support request/response mode
        function()
            if req_size and req_size < size then
                size = sock:send(self.buf:segment(req_size, size - req_size))
                print("tail request size: " .. size)

                _, size = sock:recv(self.buf)
                self.socket:send(self.buf:segment(0, size))

                print("response size: " .. size)
            end
            while true do
                _, size = self.socket:recv(self.buf)
                if size == 0 then
                    print("client disconnected")
                    break
                end
                sock:send(self.buf:segment(0, size))
                print("request size: " .. size)

                _, size = sock:recv(self.buf)
                self.socket:send(self.buf:segment(0, size))

                print("response size: " .. size)
            end
        end
    )
    print("stop handle")
    sock:close()
    self.socket:close()
end

function Client:response(cd, dstport, dstip)
    res = self.buf:layout(Head)
    res.vn = 0
    res.cd = cd
    res.dstport = dstport
    res.dstip = dstip
    self.socket:send(self.buf:segment(0, REPONSE_SIZE))
end

local server = socket.new("i", "t")
server:bind("0.0.0.0", PORT)
server:listen(5)

print("SOCKv4 start")
client = Client:new(server:accept())
client:handle()
server:close()
