#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The footprint set, sourced by bench.sh: the size of each module installed, the Lua heap of a
# runtime in each context, and the kmalloc memory /proc/slabinfo counts for an empty runtime in each
# context. A script a runtime is created with reports through print, since lunatik run and stop of
# a process script are the one part of the CLI the three API generations spell alike.
# shellcheck shell=bash disable=SC2154 # lua, ref, kernel and samples are bench.sh's

contexts=(process softirq hardirq)
runtimes=64

# runs bench/footprint, which creates <n> runtimes of <script> in <context>, and prints its lines
holder() {
	local nonce=$RANDOM$RANDOM lines
	printf 'return {script = "%s", context = "%s", n = %d, nonce = "%s"}\n' "$1" "$2" "$3" "$nonce" |
		sudo tee "$lua/params.lua" > /dev/null
	sudo lunatik run bench/footprint > /dev/null
	lines=$(sudo dmesg | grep -F "bench $nonce " || true)
	grep -q "ready$" <<< "$lines" || { echo "bench: bench/footprint did not run on $ref" >&2; exit 1; }
	echo "$lines"
}

slab() {
	# what a runtime takes from the slab is kmalloc's, and the other caches move with every task on the host
	sudo awk '/^kmalloc-/ { bytes += $2 * $4 } END { print bytes }' /proc/slabinfo
}

# the kmalloc memory bench/footprint holds with <n> empty runtimes in <context>
held() {
	local before after
	before=$(slab)
	holder bench/empty "$1" "$2" > /dev/null
	after=$(slab)
	sudo lunatik stop bench/footprint > /dev/null
	echo $((after - before))
}

footprint() {
	local ko context load0 bytes full empty field i
	local -a sizes
	load0=$(load)
	for ko in "/lib/modules/$kernel/kernel/lunatik"/*.ko; do
		read -ra sizes < <(size "$ko" | tail -1)
		i=0
		for field in text data bss; do
			echo "size.$field.$(basename "$ko" .ko),,1,${sizes[i++]},bytes,$load0,$(load)"
		done
	done
	for context in "${contexts[@]}"; do
		for ((i = 0; i < samples; i++)); do
			load0=$(load)
			bytes=$(holder bench/heap "$context" 1 | sed -n 's/.* heap //p')
			sudo lunatik stop bench/footprint > /dev/null
			echo "heap,$context,1,$bytes,bytes,$load0,$(load)"
		done
		for ((i = 0; i < samples; i++)); do
			load0=$(load)
			full=$(held "$context" "$runtimes")
			empty=$(held "$context" 0)
			echo "slab,$context,$runtimes,$(((full - empty) / runtimes)),bytes,$load0,$(load)"
		done
	done
}

