#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#

set -eux

# add namespaces ns1 for dns server ns2 for server
sudo ip netns add ns1
sudo ip netns add ns2

# add link between host and the namespaces
sudo ip link add veth1 netns ns1 type veth peer name veth2
sudo ip link add veth3 netns ns2 type veth peer name veth4

# add ip address to the links
# DNS IP : 10.1.1.3
# Server IP : 10.1.2.3
sudo ip addr add 10.1.1.2/24 dev veth2
sudo ip -n ns1 addr add 10.1.1.3/24 dev veth1
sudo ip addr add 10.1.2.2/24 dev veth4
sudo ip -n ns2 addr add 10.1.2.3/24 dev veth3

# up the interfaces
sudo ip -n ns1 link set veth1 up
sudo ip -n ns2 link set veth3 up
sudo ip link set veth2 up
sudo ip link set veth4 up

# backup resolv config
echo "Backing up resolver config to /etc/resolv.conf.lunatik"
sudo cp -fP /etc/resolv.conf /etc/resolv.conf.lunatik && \
sudo sed -i 's/nameserver/#nameserver/g' /etc/resolv.conf && \
echo "nameserver 10.1.1.3" | sudo tee -a /etc/resolv.conf && \

# run the dns server in ns1, answering lunatik.com with 192.168.10.1
sudo ip netns exec ns1 dnsmasq --keep-in-foreground --no-resolv --no-hosts --bind-interfaces \
	--listen-address=10.1.1.3 --pid-file= --address=/lunatik.com/192.168.10.1

