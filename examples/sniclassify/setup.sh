#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

set -eux

IF=${1:?usage: setup.sh <iface>}

tc qdisc add dev "$IF" root handle 1: htb default 20
tc class add dev "$IF" parent 1:  classid 1:1  htb rate 100mbit ceil 100mbit
tc class add dev "$IF" parent 1:1 classid 1:10 htb rate 50mbit  ceil 100mbit prio 1
tc class add dev "$IF" parent 1:1 classid 1:20 htb rate 30mbit  ceil 100mbit prio 2
tc class add dev "$IF" parent 1:1 classid 1:30 htb rate 20mbit  ceil 100mbit prio 3

# the CLI creates and pins the flow map, starts the runtime the program calls, loads the
# compiled classifier and attaches it to the egress hook of "$IF"
lunatik run examples/sniclassify/sni softirq percpu dev="$IF"

