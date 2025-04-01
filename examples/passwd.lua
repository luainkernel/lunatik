--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

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
