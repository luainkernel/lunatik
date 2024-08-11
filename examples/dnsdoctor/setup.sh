# SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only

#!/bin/bash

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

# make a directory to setup dns server
mkdir dnstest
cd dnstest
python -m venv .venv
source .venv/bin/activate
pip install dnserver

# backup resolv config
echo "Backing up resolver config to /etc/resolver.conf.lunatik"
sudo cp -f /etc/resolv.conf /etc/resolv.conf.lunatik && \
sudo sed -i 's/nameserver/#nameserver/g' /etc/resolv.conf && \
echo "nameserver 10.1.1.3" | sudo tee -a /etc/resolv.conf && \

# add zone info and run dns server in ns1
echo """
[[zones]]
host = 'lunatik.com'
type = 'A'
answer = '192.168.10.1'

[[zones]]
host = 'lunatik.com'
type = 'NS'
answer = 'ns1.lunatik.com.'

[[zones]]
host = 'lunatik.com'
type = 'NS'
answer = 'ns2.lunatik.com.'
""" > zones.toml
sudo ip netns exec ns1 .venv/bin/dnserver --no-upstream zones.toml

