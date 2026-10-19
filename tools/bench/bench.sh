#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Measures refs of Lunatik on this host, as doc/design/benchmark/plan.md holds it: each ref is built
# in a worktree of its own under the work directory, installed in place of what is installed, given
# the benchmark scripts of its API generation under /lib/modules/lua/bench/, and measured by each
# set, a file tools/bench/<set>.sh whose function of the same name prints one row per sample. The
# rounds rotate the order of the refs. The tree this script lives in is installed and loaded again
# when the run ends, fails or is interrupted, as long as its terminal lasts: sudo keys its ticket to
# the terminal, so a run that may outlive one goes in tmux or screen.
#
#     bash tools/lunatik-host bash tools/bench/bench.sh scratch/bench 3 footprint v4.4.1 v5.0 v5.1
#
# writes <workdir>/round<n>.csv, one row per sample, and <workdir>/summary.csv, the median and the
# interquartile range per ref, set, operation and context.

set -euo pipefail
shopt -s inherit_errexit

[ $# -ge 4 ] || { echo "usage: $0 <workdir> <rounds> <set>[,<set>...] <ref>..." >&2; exit 2; }
work=$(realpath -m "$1")
rounds=$2
IFS=, read -ra sets <<< "$3"
shift 3
refs=("$@")

bench=$(cd "$(dirname "$0")" && pwd)
home=$(git -C "$bench" rev-parse --show-toplevel)
lua=/lib/modules/lua/bench
# shellcheck disable=SC2034 # read by the sets
samples=30 # a batch, plan.md "Repetition"
kernel=$(uname -r)
tree=

for set in "${sets[@]}"; do
	# shellcheck disable=SC1090 # a set is a file the command line names
	source "$bench/$set.sh"
done

generation() {
	git -C "$home" describe --tags --abbrev=0 "$1"
}

for ref in "${refs[@]}"; do
	[ -f "$bench/names/$(generation "$ref").lua" ] ||
		{ echo "bench: no names for $ref's API generation in $bench/names" >&2; exit 2; }
done

load() {
	cut -d" " -f1 /proc/loadavg
}

retire() {
	sudo lunatik unload
	(cd "$tree" && sudo env PWD="$tree" make uninstall > /dev/null)
	sudo rm -rf "$lua"
	rm -rf "$tree"
	git -C "$home" worktree prune
	tree=
}

restore() {
	trap - EXIT
	trap "" INT TERM # a second interrupt would leave the host between two installs
	set +e
	[ -n "$tree" ] && retire
	(cd "$home" && sudo env PWD="$home" make install > /dev/null) && sudo lunatik reload && return
	echo "bench: $home is not installed back" >&2
	exit 1
}

measure() {
	local ref=$1 round=$2 set row
	local free
	# lunatik load keeps a module already loaded, so the previous build's would be measured as this ref
	[ ! -d /sys/module/lunatik ] || { echo "bench: lunatik is still loaded, not measuring $ref" >&2; exit 1; }
	free=$(df -Pm "$work" | awk 'NR == 2 { print $4 }')
	[ "$free" -ge 1024 ] || { echo "bench: $free MB free under $work, not building $ref" >&2; exit 1; }

	tree=$work/${ref//\//-}
	git -C "$home" worktree add --detach "$tree" "$ref" > /dev/null
	# the URLs of a local clone's submodules are paths, which git refuses to fetch from by default
	git -C "$tree" -c protocol.file.allow=always submodule update --init > /dev/null
	(cd "$tree" && make -j"$(nproc)" > "$tree.log" 2>&1)

	(cd "$tree" && sudo env PWD="$tree" make install > /dev/null)
	sudo install -d "$lua"
	sudo install -m 0644 "$bench"/lua/*.lua "$lua"
	sudo install -m 0644 "$bench/names/$(generation "$ref").lua" "$lua/names.lua"
	sudo lunatik load

	for set in "${sets[@]}"; do
		"$set" | while IFS= read -r row; do
			echo "$ref,$round,$set,$row,$kernel,$(date -Is)"
		done >> "$work/round$round.csv"
	done
	retire
}

summary() {
	echo "ref,set,operation,context,unit,samples,median,q1,q3,iqr"
	tail -qn +2 "$work"/round*.csv | sort -t, -k1,1 -k3,5 -k8,8 -k7,7g | awk -F, '
		function q(p,  h, i) { h = (n - 1) * p + 1; i = int(h); return x[i] + (h - i) * (x[i + 1] - x[i]) }
		function flush() { if (n) printf "%s,%d,%.10g,%.10g,%.10g,%.10g\n", key, n, q(0.5), q(0.25), q(0.75), q(0.75) - q(0.25) }
		{ k = $1 "," $3 "," $4 "," $5 "," $8 }
		k != key { flush(); key = k; n = 0 }
		{ x[++n] = $7 }
		END { flush() }'
}

mkdir -p "$work"
rm -f "$work"/round*.csv "$work/summary.csv" # summary reads every round file, a previous run's among them
(cd "$home" && make -j"$(nproc)" > "$work/build.log" 2>&1)
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sudo lunatik unload
(cd "$home" && sudo env PWD="$home" make uninstall > /dev/null)

for ((round = 1; round <= rounds; round++)); do
	echo "ref,round,set,operation,context,n,value,unit,load0,load1,kernel,time" > "$work/round$round.csv"
	for ((i = 0; i < ${#refs[@]}; i++)); do
		measure "${refs[(i + round - 1) % ${#refs[@]}]}" "$round"
	done
done
summary > "$work/summary.csv"

