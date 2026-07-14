#!/bin/bash

TC="tc"
IF="wlp3s0"
BPF_OBJ="examples/qos/classify.o"
SEC_NAME="classifier"

# 1. cleanup
echo "Cleaning up existing qdiscs and filters..."
$TC filter del dev $IF egress 2>/dev/null
$TC qdisc del dev $IF clsact 2>/dev/null
$TC qdisc del dev $IF root 2>/dev/null

# 2. create htb scheduler
echo "Setting up HTB scheduler..."
$TC class add dev $IF parent 1: classid 1:1 htb rate 100mbit ceil 100mbit

# Band 1: Interactive / Tiny Packets (<256B) - High Priority
$TC class add dev $IF parent 1:1 classid 1:10 htb rate 50mbit ceil 100mbit prio 1

# Band 2: Normal / Standard flows (<800B) - Medium Priority
$TC class add dev $IF parent 1:1 classid 1:20 htb rate 30mbit ceil 100mbit prio 2

# Band 3: Bulk / Large transfers (>800B) - Low Priority
$TC class add dev $IF parent 1:1 classid 1:30 htb rate 20mbit ceil 100mbit prio 3

# 3. create clsact hook
echo "Creating clsact hook..."
$TC qdisc add dev $IF clsact

# 4. load and attach ebpf classifier
echo "Loading eBPF classifier onto egress..."
$TC filter add dev $IF egress bpf da obj $BPF_OBJ sec $SEC_NAME

echo "Setup complete! Verifying status:"
echo "-----------------------------------"
$TC qdisc show dev $IF
echo "-----------------------------------"
$TC class show dev $IF

