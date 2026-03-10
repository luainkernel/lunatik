#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

set -eux

lunatik stop examples/tcpreject/nf_tcpreject
nft delete table ip tcpreject
nft delete table ip6 tcpreject
ip link del veth-tcpreject
ip netns del tcpreject
echo 0 > /proc/sys/net/ipv4/ip_forward
echo 0 > /proc/sys/net/ipv6/conf/all/forwarding

