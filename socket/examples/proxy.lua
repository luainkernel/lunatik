local PORT = 8080

Client = {}
Head =
    data.layout {
    vn = {0, 8},
    cd = {8, 8},
    dstport = {16, 16, "host"},
    dstip = {32, 32, "host"}
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
    -- assert(self.buf:segment(size - 1, 1):layout {null = {0, 8}} == 0)

    req = self.buf:layout(Head)
    -- only support SOCKS4 and CONNECT command now
    if req.vn ~= 4 or req.cd ~= Command.connect then
        print("Not SOCKS4 or is bind")
        self:response(Command.rejected, req.dstport, req.dstip)
        self.socket:close()

        return
    end

    local sock = socket.new("i", "t")
    local state, err = pcall(sock.connect, sock, req.dstip, req.dstport)
    if not state then
        print("connect failed: " .. err)
        self:response(Command.rejected, req.dstport, req.dstip)
        self.socket:close()

        return
    end

    self:response(Command.granted, req.dstport, req.dstip)
    self.target_socket = sock
    pcall(
        -- only support request/response mode
        function()
            while true do
                _, size = self.socket:recv(self.buf)
                sock:send(self.buf:segment(0, size))
            end
        end
    )
    sock:clsoe()
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

client = Client:new(server:accept())
client:handle()
