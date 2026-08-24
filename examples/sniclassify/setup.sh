#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

set -eux

IF=${1:?usage: setup.sh <iface>}
DIR=$(dirname "$(readlink -f "$0")")
PIN=/sys/fs/bpf/sniclassify

lunatik run examples/sniclassify/sni softirq percpu

tc qdisc add dev "$IF" root handle 1: htb default 20
tc class add dev "$IF" parent 1:  classid 1:1  htb rate 100mbit ceil 100mbit
tc class add dev "$IF" parent 1:1 classid 1:10 htb rate 50mbit  ceil 100mbit prio 1
tc class add dev "$IF" parent 1:1 classid 1:20 htb rate 30mbit  ceil 100mbit prio 2
tc class add dev "$IF" parent 1:1 classid 1:30 htb rate 20mbit  ceil 100mbit prio 3

# load with bpftool (current libbpf), then attach the pinned program, so this does
# not depend on the distribution's iproute2 being new enough to load the object
tc qdisc add dev "$IF" clsact
bpftool prog load "$DIR/classify.o" "$PIN"
tc filter add dev "$IF" egress bpf da object-pinned "$PIN"

