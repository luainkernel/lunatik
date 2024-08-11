# SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only

#!/bin/bash

set -eux

rm dnstest -rf

# backup resolv config
if [[ -f /etc/resolv.conf.lunatik ]] then
	echo "Restoring dns config from resolv.conf.lunatik"
	sudo rm /etc/resolv.conf
	sudo cp /etc/resolv.conf.lunatik /etc/resolv.conf
	sudo rm /etc/resolv.conf.lunatik
fi

# down the interfaces
sudo ip -n ns1 link set veth1 down
sudo ip -n ns2 link set veth3 down
sudo ip link set veth2 down
sudo ip link set veth4 down

sudo ip addr delete 10.1.1.2/24 dev veth2
sudo ip -n ns1 addr delete 10.1.1.3/24 dev veth1
sudo ip addr delete 10.1.2.2/24 dev veth4
sudo ip -n ns2 addr delete 10.1.2.3/24 dev veth3

# delete link between host and the namespaces
sudo ip -n ns1 link delete veth1
sudo ip -n ns2 link delete veth3

# delete namespaces ns1 for dns server ns2 for server
sudo ip netns delete ns1
sudo ip netns delete ns2

