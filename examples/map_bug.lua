local map = require("ebpf.map")

local stats = map.open("/sys/fs/bpf/flow_stats")

