# Lunatik Socket Library Documention

<!-- TOC -->

- [Lunatik Socket Library Documention](#lunatik-socket-library-documention)
    - [`socket.new()`](#socketnew)
        - [Syntax](#syntax)
        - [Parameters](#parameters)
        - [Returns](#returns)
        - [Example](#example)
    - [`socket:bind()`](#socketbind)
        - [Syntax](#syntax-1)
        - [Parameters](#parameters-1)
        - [Returns](#returns-1)
        - [Example](#example-1)
    - [`socket:listen()`](#socketlisten)
        - [Syntax](#syntax-2)
        - [Parameters](#parameters-2)
        - [Returns](#returns-2)
        - [Example](#example-2)
    - [`socket:accept()`](#socketaccept)
        - [Syntax](#syntax-3)
        - [Parameters](#parameters-3)
        - [Returns](#returns-3)
        - [Example](#example-3)
    - [`socket:connect()`](#socketconnect)
        - [Syntax](#syntax-4)
        - [Parameters](#parameters-4)
        - [Returns](#returns-4)
        - [Example](#example-4)
    - [`socket:recvmsg()`](#socketrecvmsg)
        - [Syntax](#syntax-5)
        - [Parameters](#parameters-5)
        - [Returns](#returns-5)
        - [Example](#example-5)
    - [`socket:sendmsg()`](#socketsendmsg)
        - [Syntax](#syntax-6)
        - [Parameters](#parameters-6)
        - [Returns](#returns-6)
        - [Example](#example-6)
    - [`socket:recv()`](#socketrecv)
        - [Syntax](#syntax-7)
        - [Parameters](#parameters-7)
        - [Returns](#returns-7)
        - [Example](#example-7)
    - [`socket:send()`](#socketsend)
        - [Syntax](#syntax-8)
        - [Parameters](#parameters-8)
        - [Returns](#returns-8)
        - [Example](#example-8)
    - [`socket:close()`](#socketclose)
        - [Syntax](#syntax-9)
        - [Parameters](#parameters-9)
        - [Returns](#returns-9)
        - [Example](#example-9)
    - [`socket:getsockname()`](#socketgetsockname)
        - [Syntax](#syntax-10)
        - [Parameters](#parameters-10)
        - [Returns](#returns-10)
        - [Example](#example-10)
    - [`socket:getpeername()`](#socketgetpeername)
        - [Syntax](#syntax-11)
        - [Parameters](#parameters-11)
        - [Returns](#returns-11)
        - [Example](#example-11)
    - [`socket:getsockopt()`](#socketgetsockopt)
        - [Syntax](#syntax-12)
        - [Parameters](#parameters-12)
        - [Returns](#returns-12)
        - [Example](#example-12)
    - [`socket:setsockopt()`](#socketsetsockopt)
        - [Syntax](#syntax-13)
        - [Parameters](#parameters-13)
        - [Returns](#returns-13)
        - [Example](#example-13)
    - [`socket.poll()`](#socketpoll)
        - [Syntax](#syntax-14)
        - [Parameters](#parameters-14)
        - [Returns](#returns-14)
        - [Example](#example-14)
    - [`lpoll:select()`](#lpollselect)
        - [Syntax](#syntax-15)
        - [Parameters](#parameters-15)
        - [Returns](#returns-15)
        - [Example](#example-15)

<!-- /TOC -->

## `socket.new()`

Create a new socket.

### Syntax

`socket.new()`

### Parameters

- `family` string value `inet` or `i`
- `type` string value `tcp`, `udp`, `t` or `u`

### Returns

- `luasocket` sub module

### Example

```lua
sock = socket.new('i', 't')
```

## `socket:bind()`

Bind a socket to a specific address. When bind fails, this function will raise an error with an error code.

### Syntax

`socket.sock:bind(ip, port)`

### Parameters

- `addr` string or integer - address
- `port` integer - port number

### Returns

- `nil`

### Example

```lua
sock = socket.new('i', 't')
sock:bind("127.0.0.1", 6666)
```

## `socket:listen()`

Start listening new connection. When listen fails, this function will raise an error with an error code.

### Syntax

`socket.sock:listen(backlog)`

### Parameters

- `backlog` integer

### Returns

- `nil`

### Example

```lua
sock = socket.new('i', 't')
sock:bind("127.0.0.1", 6666)
sock:listen(10)
```

## `socket:accept()`

Accept an established connection. When accept fails, this function will raise an error with an error code.

### Syntax

`socket.sock:accept([flags])`

### Parameters

- `nil`

### Returns

- `luasocket` - the new client socket

### Example

```lua
sock = socket.new('i', 't')
sock:bind("127.0.0.1", 6666)
sock:listen(10)
client = sock:accept()
```

## `socket:connect()`

Connect to specific socket. When connect fails, this function will raise an error with an error code.

### Syntax

`socket.sock:connect(ip, port [, flags])`

### Parameters

- `ip` string or integer - address
- `port` integer - port number
- `flags` integer, default 0

### Returns

- `nil`

### Example

```lua
sock = socket.new('i', 't')
sock:connect("127.0.0.1", 8888)
```

## `socket:recvmsg()`

Receive a message. When recvmsg fails, this function will raise an error with an error code.

### Syntax

`socket:recvmsg(msghdr[, buffer][, flags])`

### Parameters

- `msghdr` table - represent `struct msghdr`. For example,

    ```lua
    msghdr = {
        name = {ip, port},
        lov_len = #data
    }
    ```

- `buffer` when `CONFIG_LUADATA` is enabled, a data object can be passed to receive data

- `flags` string - like `D` means `MSG_DONTWAIT`

### Returns

- `data` - a table or a data object
- `size` - the length of data
- `msghdr` - the message header of data

### Example

```lua
local d, size, header = sock:recvmsg({iov_len = 5})
-- or
local buf = data.new(3)
sock:recvmsg({}, buf)
```

## `socket:sendmsg()`

Write a socket. When sendmsg fails, this function will raise an error with an error code.

### Syntax

`socket:sendmsg(msghdr[, data])`

### Parameters

- `msghdr` table - represent `struct msghdr`. For example,

    ```lua
    msghdr = {
        name = {ip, port},
        lov_len = #data
    }
    ```

- `data` a table or a data object

### Returns

- `size` - the length of data

### Example

```lua
local size = sock:sendmsg({}, {1, 2, 3})
-- or
local buf = data.new(3)
sock:sendmsg({}, buf)
```

## `socket:recv()`

Receive a message. When recvmsg fails, this function will raise an error with an error code.

### Syntax

`socket:recv(buffer | size)`

### Parameters

- `buffer` when `CONFIG_LUADATA` is enabled, a data object can be passed to receive data

- `size` integer - length, can not be used with buffer together

### Returns

- `data` - a table or a data object
- `size` - the length of data

### Example

```lua
local d, size, header = sock:recv(5)
-- or
local buf = data.new(3)
sock:recv({buf)
```

## `socket:send()`

Write a socket. When sendmsg fails, this function will raise an error with an error code.

### Syntax

`socket:sendmsg(data)`

### Parameters

- `data` a table or a data object

### Returns

- `size` - the length of data

### Example

```lua
local size = sock:send{1, 2, 3}
-- or
local buf = data.new(3)
sock:send(buf)
```

## `socket:close()`

Release socket. When `sock_release` fails, this function will raise an error with an error code.

### Syntax

`socket:close()`

### Parameters

- `nil`

### Returns

- `nil`

### Example

```lua
sock = socket.new('i', 't')
sock:connect("127.0.0.1", 8888)
sock:close()
```

## `socket:getsockname()`

Get local name. When `kernel_getsockname` fails, this function will raise an error with an error code.

### Syntax

`socket:gethostname()`

### Parameters

- `nil`

### Returns

- string - ip
- integer - port

### Example

```lua
ip, port = sock:getsockname()
```

## `socket:getpeername()`

Get remote name. When `kernel_getpeername` fails, this function will raise an error with an error code.

### Syntax

`socket:getpeername()`

### Parameters

- `nil`

### Returns

- string - ip
- integer - port

### Example

```lua
ip, port = sock:getpeername()
```

## `socket:getsockopt()`

Get the socket option. When `kernel_getsockopt` fails, this function will raise an error with an error code.

### Syntax

`socket.sock:getsockopt(level, optname)`

### Parameters

- `level` string in `socket.level`
- `optname` string in `socket.optname`

### Returns

- `val` array - it's mean depends on the option

### Example

```lua
sock = socket.new('i', 't')
sock:connect("127.0.0.1", 8888)
recv_buf = sock:setsockopt('s', 'r')
```

## `socket:setsockopt()`

Set the socket option. When `kernel_setsockopt` fails, this function will raise an error with an error code.

### Syntax

`socket.sock:setsockopt(level, optname, val)`

### Parameters

- `level` string
- `optname` string
- `val` integer

### Returns

- `nil`

### Example

```lua
sock = socket.new('i', 't')
sock:connect("127.0.0.1", 8888)
sock:setsockopt('s', 'r', 1000)
```

## `socket.poll()`

Create a `lpoll` object, which repesents a set of sockets.

### Syntax

`socket.poll(socks)`

### Parameters

- `socks` a table of sockets

### Returns

- `lpoll` obejct

### Example

```lua
local server = socket.new("i", "t")
server:bind("0.0.0.0", 8080)
server:listen(5)

local client = socket.new("i", "t")
client:connect("127.0.0.1", 12345)

local remote = server:accept()

local poll = socket.poll{remote, client}
```

## `lpoll:select()`

I/O multiplexing function, indicating some events happening. This function may block until a socket receives some data.

### Syntax

`lpoll:select()`

### Parameters

- `nil`

### Returns

- `luasocket` obejct - a socket with data available

### Example

```lua
local server = socket.new("i", "t")
server:bind("0.0.0.0", 8080)
server:listen(5)

local client = socket.new("i", "t")
client:connect("127.0.0.1", 12345)

local remote = server:accept()

local poll = socket.poll{remote, client}

client:send({1, 2, 3})

print("start select")

local index = lpoll:select()

print("select result: " .. index)
```