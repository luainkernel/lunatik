#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#

set -ux

# delete link between host and the namespaces
sudo ip link delete veth2
sudo ip link delete veth4

# delete namespaces ns1 for dns server ns2 for server
sudo ip netns delete ns1
sudo ip netns delete ns2

