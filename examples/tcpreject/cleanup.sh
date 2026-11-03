#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#

set -eux

lunatik stop examples/tcpreject/nf_tcpreject || true # a reload, or a script never run, leaves nothing to stop
nft delete table ip tcpreject
nft delete table ip6 tcpreject
ip link del veth-tcpreject
ip netns del tcpreject
sysctl -p /run/tcpreject.sysctl
rm /run/tcpreject.sysctl

