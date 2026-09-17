#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Measures what a call into the kernel Lua VM costs on the tree's own XDP path: a
# native XDP_PASS program against the same program calling bpf_luaxdp_run, with a
# callback that only sets the verdict and one that reads a packet byte first, each
# in a plain and in a percpu runtime. pktgen floods a veth pair whose peer sits in
# a network namespace, and every program counts the packets it ran on in a per-CPU
# array, so the count is the hook's own rather than the interface's.
#
# percpu is the pin, not the lock: lunatik_lock takes spin_lock_bh for a softirq
# runtime either way, and what lunatik_pin removes is the cross-CPU contention on
# one shared runtime object. With a single generating CPU there is none to remove.
#
# Three things the table does not say. A veth pair is not a NIC, so the per-packet
# cost is the pair's and not a driver's. The generator and the hook share the
# receiving CPU, so they compete for it; under a flood the receive softirq can
# spill onto a second CPU and the row then goes faster for a reason that is not
# the code, so no delta is quoted unless every row ran on the same CPUs. The
# absolute rate is therefore the pair's; what the trampoline costs is the
# row-to-row difference, 1/pps - 1/pps_native, in which the generator's
# per-packet cost cancels.
#
# Usage: sudo bash tools/bench/xdp.sh
#        LUNATIK_BENCH_SECONDS=<n>  generation window per run, default 10
#        LUNATIK_BENCH_RUNS=<n>     runs per row, default 3
#        LUNATIK_BENCH_CPUS="<ids>" generating CPUs, default 0
#        LUNATIK_BENCH_MISSED=<n>   percent missed above which no delta is quoted, default 1

IFACE="lunatikb0"
PEER="lunatikb1"
NETNS="lunatik_bench"
PIN="/sys/fs/bpf/bench_prog"
SCRIPTS="/lib/modules/lua/bench"
TARGET="10.199.0.1"
SOURCE="10.199.0.2"
MAP="bench_counters"
MODULE="luaxdp"
PKT_SIZE=64
CLONE_SKB=0 # a cloned skb is shared, and the XDP path unshares it: one copy per packet, on every row
SHARE=1 # percent of a row's packets a CPU must carry to count as one the row ran on

WINDOW=${LUNATIK_BENCH_SECONDS:-10}
RUNS=${LUNATIK_BENCH_RUNS:-3}
CPUS=${LUNATIK_BENCH_CPUS:-0}
MISSED=${LUNATIK_BENCH_MISSED:-1}

# label | object | callback script | lunatik run options, which is also the context
# column; a later phase measuring a compiled program adds a row here
rows=(
	"native|xdp_native.bpf.o|-|-"
	"verdict|xdp_verdict.bpf.o|bench/verdict|softirq"
	"verdict percpu|xdp_verdict.bpf.o|bench/verdict|softirq percpu"
	"byte|xdp_byte.bpf.o|bench/byte|softirq"
	"byte percpu|xdp_byte.bpf.o|bench/byte|softirq percpu"
)

DIR="$(dirname "$(readlink -f "$0")")"
TMP=""

die()
{
	echo "$1" >&2
	exit 1
}

netns_sh()
{
	ip netns exec "$NETNS" bash -c "$1"
}

pg_write()
{
	netns_sh "echo '$2' > /proc/net/pktgen/$1"
}

cleanup()
{
	local cpu row script
	bpftool net detach xdp dev "$IFACE" 2> /dev/null
	rm -f "$PIN"
	for row in "${rows[@]}"; do
		IFS='|' read -r _ _ script _ <<< "$row"
		[ "$script" = "-" ] || lunatik stop "$script" > /dev/null 2>&1
	done
	pg_write pgctrl stop > /dev/null 2>&1
	for cpu in $CPUS; do
		pg_write "kpktgend_$cpu" rem_device_all > /dev/null 2>&1
	done
	ip netns del "$NETNS" 2> /dev/null
	ip link del "$IFACE" 2> /dev/null
	rm -rf "$SCRIPTS"
	if [ -n "$TMP" ]; then
		rm -rf "$TMP"
	fi
}

setup()
{
	local mac peer_mac cpu queues
	make -C "$DIR" > /dev/null || die "couldn't build the bench programs"
	mkdir -p "$SCRIPTS"
	install -m 0644 "$DIR"/*.lua "$SCRIPTS" || die "couldn't install the callbacks into $SCRIPTS"

	ip netns add "$NETNS" || die "couldn't create the $NETNS namespace"
	# one rx queue per CPU: veth picks the queue from the frame's mapping and polls it on the
	# CPU that filled it, so a single queue would funnel every generating CPU into one hook
	queues=$(nproc)
	ip link add "$IFACE" numrxqueues "$queues" numtxqueues "$queues" \
		type veth peer name "$PEER" numrxqueues "$queues" numtxqueues "$queues" ||
		die "couldn't create the $IFACE veth pair"
	ip link set "$PEER" netns "$NETNS"
	ip addr add "$TARGET/24" dev "$IFACE"
	ip link set "$IFACE" up
	netns_sh "ip addr add $SOURCE/24 dev $PEER"
	netns_sh "ip link set $PEER up"

	# pin the neighbour entries so ARP never competes with the generated frames
	mac=$(cat "/sys/class/net/$IFACE/address")
	peer_mac=$(netns_sh "cat /sys/class/net/$PEER/address")
	ip neigh replace "$SOURCE" lladdr "$peer_mac" dev "$IFACE" nud permanent
	netns_sh "ip neigh replace $TARGET lladdr $mac dev $PEER nud permanent"

	modprobe pktgen || die "couldn't load pktgen"
	netns_sh "[ -d /proc/net/pktgen ]" || die "couldn't find /proc/net/pktgen in $NETNS"
	for cpu in $CPUS; do
		pg_write "kpktgend_$cpu" rem_device_all > /dev/null
		pg_write "kpktgend_$cpu" "add_device $PEER@$cpu" > /dev/null ||
			die "couldn't give $PEER@$cpu to the pktgen thread of CPU $cpu"
		pg_write "$PEER@$cpu" "count 0" > /dev/null
		pg_write "$PEER@$cpu" "clone_skb $CLONE_SKB" > /dev/null
		pg_write "$PEER@$cpu" "pkt_size $PKT_SIZE" > /dev/null
		pg_write "$PEER@$cpu" "dst $TARGET" > /dev/null
		pg_write "$PEER@$cpu" "dst_mac $mac" > /dev/null
		pg_write "$PEER@$cpu" "flag QUEUE_MAP_CPU" > /dev/null
	done
}

map_id()
{
	local ids id
	ids=$(bpftool prog show pinned "$PIN" | sed -n 's/.*map_ids \([0-9,]*\).*/\1/p' | tr ',' ' ')
	for id in $ids; do
		if bpftool map show id "$id" | grep -q "name $MAP"; then
			echo "$id"
			return 0
		fi
	done
	return 1
}

# echoes "processed refused", and writes the per-CPU processed count to $2
counters()
{
	bpftool map dump id "$1" | awk -v percpu="$2" '
		/"key":/   { key = $2 + 0 }
		/"cpu":/   { cpu = $2 + 0 }
		/"value":/ {
			total[key] += $2 + 0
			if (key == 0)
				print cpu, $2 + 0 > percpu
		}
		END { printf "%d %d\n", total[0], total[1] }'
}

cpu_stat()
{
	grep '^cpu[0-9]' /proc/stat > "$1"
}

# per-CPU busy and softirq share of the window between the two /proc/stat samples
cpu_load()
{
	awk '
		NR == FNR {
			for (field = 2; field <= NF; field++)
				before[$1, field] = $field
			next
		}
		{
			total = 0
			for (field = 2; field <= NF; field++) {
				delta[field] = $field - before[$1, field]
				total += delta[field]
			}
			if (total <= 0)
				next
			busy = total - delta[5] - delta[6] # idle and iowait
			printf "%s %.1f %.1f\n", substr($1, 4), 100 * busy / total, 100 * delta[8] / total
		}' "$1" "$2"
}

delta_split()
{
	awk 'NR == FNR { before[$1] = $2; next } { print $1, $2 - before[$1] }' "$1" "$2"
}

# the CPUs a row ran on, in id order: two rows' rates compare only when this is the same
split_cpus()
{
	sort -n "$1" | awk -v share="$SHARE" '
		{ cpu[NR] = $1; packets[NR] = $2; total += $2 }
		END {
			for (row = 1; row <= NR; row++)
				if (100 * packets[row] / total >= share)
					printf "%s ", cpu[row]
		}'
}

# echoes "generated usec": what every generating thread sent, and the widest window
pg_result()
{
	local cpu line packets=0 usec=0 sent window
	for cpu in $CPUS; do
		line=$(netns_sh "cat /proc/net/pktgen/$PEER@$cpu" |
			sed -n 's/^Result: OK: \([0-9]*\)(.*) usec, \([0-9]*\) .*/\1 \2/p')
		[ -n "$line" ] || return 1
		read -r window sent <<< "$line"
		packets=$((packets + sent))
		if [ "$window" -gt "$usec" ]; then
			usec=$window
		fi
	done
	echo "$packets $usec"
}

generate()
{
	local starter
	netns_sh "echo start > /proc/net/pktgen/pgctrl" &
	starter=$!
	sleep "$WINDOW"
	pg_write pgctrl stop > /dev/null
	wait "$starter" || die "the generator did not run" # a stale Result would read as this run's
}

start_runtime()
{
	local script="$1" options="$2" output
	output=$(lunatik run "$script" $options 2>&1) # run exits 0 on a failed load: the error is its output
	[ -z "$output" ] || die "couldn't run $script: $output"
	[ -f "/sys/kernel/btf/$MODULE" ] || die "$MODULE built without BTF (make btf_install, rebuild)"
}

measure()
{
	local index="$1" run="$2"
	local label object script options
	local id result generated usec processed refused was_processed was_refused pps
	IFS='|' read -r label object script options <<< "$3"

	[ "$script" = "-" ] || start_runtime "$script" "$options"
	bpftool prog load "$DIR/$object" "$PIN" type xdp || die "couldn't load $object"
	bpftool net attach xdp pinned "$PIN" dev "$IFACE" || die "couldn't attach $object to $IFACE"
	id=$(map_id) || die "couldn't find the $MAP map of $object"

	read -r was_processed was_refused <<< "$(counters "$id" "$TMP/split.before")"
	cpu_stat "$TMP/stat.before"
	generate
	cpu_stat "$TMP/stat.after"
	read -r processed refused <<< "$(counters "$id" "$TMP/split.after")"

	bpftool net detach xdp dev "$IFACE"
	rm -f "$PIN"
	[ "$script" = "-" ] || lunatik stop "$script" > /dev/null

	processed=$((processed - was_processed))
	refused=$((refused - was_refused))
	result=$(pg_result) || die "$label: the generator reported no result"
	read -r generated usec <<< "$result"
	[ "$generated" -gt 0 ] || die "$label: the generator sent nothing"
	[ "$processed" -gt 0 ] || die "$label: the program ran on no packet"
	[ "$refused" -eq 0 ] || die "$label: $refused of $processed packets were not dispatched to $script"

	pps=$(awk -v packets="$processed" -v usec="$usec" 'BEGIN { printf "%.1f", packets * 1000000 / usec }')
	echo "$pps $run" >> "$TMP/pps.$index"
	echo "$processed|$generated|$usec|$pps" > "$TMP/run.$index.$run"
	cpu_load "$TMP/stat.before" "$TMP/stat.after" > "$TMP/load.$index.$run"
	delta_split "$TMP/split.before" "$TMP/split.after" > "$TMP/packets.$index.$run"
}

median_run()
{
	sort -n "$TMP/pps.$1" | awk -v rank="$(((RUNS + 1) / 2))" 'NR == rank { print $2 }'
}

table()
{
	local index label object script context median sorted
	: > "$TMP/table"
	for index in "${!rows[@]}"; do
		IFS='|' read -r label object script context <<< "${rows[$index]}"
		median=$(median_run "$index")
		sorted=$(sort -n "$TMP/pps.$index" | cut -d' ' -f1)
		printf '%s|%s|%s|%s|%s|%s\n' "$label" "$context" "$(cat "$TMP/run.$index.$median")" \
			"$(echo "$sorted" | head -1)" "$(echo "$sorted" | tail -1)" \
			"$(split_cpus "$TMP/packets.$index.$median")" >> "$TMP/table"
	done

	awk -F'|' -v limit="$MISSED" '
		BEGIN {
			printf "%-15s %-15s %12s %7s %11s %11s %11s %9s %12s %12s %8s\n", "row", "context", \
				"packets", "secs", "pps", "pps min", "pps max", "ns/pkt", "over native", "dispatched", "missed"
		}
		{
			label[NR] = $1; context[NR] = $2; packets[NR] = $3
			generated[NR] = $4; usec[NR] = $5; pps[NR] = $6; low[NR] = $7; high[NR] = $8; cpus[NR] = $9
			missed[NR] = 100 * (generated[NR] - packets[NR]) / generated[NR]
			if (missed[NR] > limit || missed[NR] < -limit)
				reason = sprintf("a row missed more than %s%% of what it was sent", limit)
			if (cpus[NR] != cpus[1])
				reason = "the rows did not all run on the same CPUs"
			rows = NR
		}
		END {
			native = 1000000000 / pps[1]
			for (row = 1; row <= rows; row++) {
				cost = 1000000000 / pps[row]
				over = (row == 1 || reason != "") ? "-" : sprintf("%.2f", cost - native)
				printf "%-15s %-15s %12d %7.2f %11.1f %11.1f %11.1f %9.2f %12s %12s %7.2f%%\n", \
					label[row], context[row], packets[row], usec[row] / 1000000, pps[row], \
					low[row], high[row], cost, over, row == 1 ? "-" : packets[row], missed[row]
			}
			if (reason != "")
				printf "\nthe run did not settle: %s, no delta quoted\n", reason
		}' "$TMP/table"
}

per_cpu()
{
	local index label median
	printf '\nper-CPU over the median run: busy and softirq share of the window, packets from the program map\n\n'
	printf '%-15s %5s %8s %10s %14s\n' "row" "cpu" "busy%" "softirq%" "packets"
	for index in "${!rows[@]}"; do
		IFS='|' read -r label _ <<< "${rows[$index]}"
		median=$(median_run "$index")
		awk -v label="$label" '
			NR == FNR { packets[$1] = $2; next }
			{ printf "%-15s %5s %8s %10s %14d\n", label, $1, $2, $3, packets[$1] }' \
			"$TMP/packets.$index.$median" "$TMP/load.$index.$median"
	done
}

header()
{
	local model
	model=$(sed -n 's/^model name[\t ]*: *//p' /proc/cpuinfo | head -1)
	printf '# %s, %s CPUs, kernel %s\n' "$model" "$(nproc)" "$(uname -r)"
	printf '# pktgen: %s-byte frames, clone_skb %s, CPU %s, %sx%ss per row\n' \
		"$PKT_SIZE" "$CLONE_SKB" "${CPUS// /,}" "$RUNS" "$WINDOW"
	printf '# link: veth %s <-> %s, peer in netns %s\n\n' "$IFACE" "$PEER" "$NETNS"
}

[ "$(id -u)" = 0 ] || die "must run as root: sudo bash tools/bench/xdp.sh"
command -v bpftool > /dev/null 2>&1 || die "couldn't find bpftool"
command -v clang > /dev/null 2>&1 || die "couldn't find clang"

trap cleanup EXIT
cleanup # clears an interrupted run's own leftovers, so the check below refuses only a foreign script
running=$(lunatik list) || die "couldn't reach /dev/lunatik"
[ -z "$running" ] || die "a lunatik script is already running: $running"

TMP=$(mktemp -d) || die "couldn't create a scratch directory"
setup

for index in "${!rows[@]}"; do
	IFS='|' read -r label _ <<< "${rows[$index]}"
	echo "# measuring $label, $RUNS x ${WINDOW}s" >&2
	: > "$TMP/pps.$index"
	for run in $(seq 1 "$RUNS"); do
		measure "$index" "$run" "${rows[$index]}"
	done
done

header
table
per_cpu

