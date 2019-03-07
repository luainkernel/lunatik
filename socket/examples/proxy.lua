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
    self.client_socket = socket
    self.buf = data.new(buf_size or 4096)
    self.addr, self.port = socket:getpeername()
    return o
end

function Client:handle()
    assert(self.client_socket ~= nil)
    print("start handle " .. self.addr .. ":" .. self.port)
    local _, size = self.client_socket:recv(self.buf)

    assert(size >= REQUEST_MIN)
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
        self.client_socket:close()

        return
    end

    print("try establish connection to " .. req.dstip .. ":" .. req.dstport)
    local sock = socket.new("i", "t")
    local state, err = pcall(sock.connect, sock, req.dstip, req.dstport)
    if not state then
        print("connect failed: " .. err)
        self:response(Command.rejected, req.dstport, req.dstip)
        self.client_socket:close()

        return
    end

    print("establish connection ok")
    self:response(Command.granted, req.dstport, req.dstip)
    self.target_socket = sock
    state, err =
        pcall(
        -- only support request/response mode
        function()
            if req_size and req_size < size then
                size = sock:send(self.buf:segment(req_size, size - req_size))
                print("tail request size: " .. size)
            end
            local poll = socket.poll {self.client_socket, self.target_socket}
            while true do
                local idx = poll:select()
                -- print("select" .. idx)
                if idx == 0 then
                    state, err, size = pcall(self.client_socket.recvmsg, self.client_socket, {}, self.buf)
                    if state then
                        if size == 0 then
                            print("client disconnected")
                            return
                        end
                        self.target_socket:send(self.buf:segment(0, size))
                        -- print("forward to target: " .. size)
                    end
                else
                    state, err, size = pcall(self.client_socket.recvmsg, self.target_socket, {}, self.buf)
                    if state then
                        if size == 0 then
                            print("target disconnected")
                            return
                        end
                        self.client_socket:send(self.buf:segment(0, size))
                        -- print("forward to client: " .. size)
                    end
                end
            end
        end
    )
    if not state then
        print("loop error: " .. err)
    end
    print("stop handle")
    sock:close()
    self.client_socket:close()
end

function Client:response(cd, dstport, dstip)
    res = self.buf:layout(Head)
    res.vn = 0
    res.cd = cd
    res.dstport = dstport
    res.dstip = dstip
    self.client_socket:send(self.buf:segment(0, REPONSE_SIZE))
end

local server = socket.new("i", "t")
server:bind("0.0.0.0", PORT)
server:listen(5)

print("SOCKSv4 start")
while true do
    client = Client:new(server:accept())
    client:handle()
end
server:close()
