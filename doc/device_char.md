# device.char Module

The `device.char` module provides a higher-level API for creating character devices with sensible defaults.

## Overview

Creating character devices in Lunatik often requires setting up common defaults like `open` and `release` handlers. This module simplifies this process by providing default implementations for these and other common operations.

## Usage

```lua
local chardev = require("device.char")

-- Create a device with just a name (all defaults applied)
chardev.new("mydevice")

-- Create a device with custom properties
local s = linux.stat
local mydev = {
    name = "mydevice",
    mode = s.IRUGO | s.IWUGO,  -- Custom mode
    read = function(self)      -- Custom read function
        return "Hello, world!\n"
    end
}
chardev.new(mydev)
```

## Default Values

The module sets the following defaults:

- `open`: A no-operation function
- `release`: A no-operation function
- `read`: Returns an empty string
- `write`: Returns 0 (indicating no bytes written)
- `ioctl`: A no-operation function
- `mode`: `s.IRUGO` (readable by all users)

## Example: Password File

Here's an example of creating a read-only device that acts like a password file:

```lua
local chardev = require("device.char")
local linux = require("linux")

local passwd = {
    name = "passwd",
    mode = linux.stat.IRUGO  -- Read-only for all users
}

function passwd:read()
    return "root:x:0:0:root:/root:/bin/bash\n" ..
           "daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin\n" ..
           "bin:x:2:2:bin:/bin:/usr/sbin/nologin\n" ..
           "sys:x:3:3:sys:/dev:/usr/sbin/nologin\n" ..
           "sync:x:4:65534:sync:/bin:/bin/sync\n"
end

chardev.new(passwd)
```

After running this script, you can read the contents with:

```
cat /dev/passwd
```

## Example: Network Tap

The module is used in the tap.lua example to create a device that captures network packets:

```lua
local chardev = require("device.char")
local socket_lib = require("socket")
local linux = require("linux")

-- ... (socket setup code) ...

local tap = {name = "tap", mode = linux.stat.IRUGO}

function tap:read()
    -- ... (packet capture code) ...
    return string.format("%X\t%X\t%X\t%d\n", dst, src, ethtype, #frame)
end

chardev.new(tap)
```

This creates a `/dev/tap` device that outputs captured network packets when read.
