#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that a `lunatik run` failing at any step leaves nothing behind: no pin root, no registered
# runtime and nothing on the device, and exits 1 with the step's own message. One row per step,
# each with the stimulus that fails it.
#   - the verifier rejects the program, which libbpf loads after it has created and pinned the maps
#   - the kernel script raises, with the object loaded and its maps pinned
#   - the device the command line names does not exist, with the runtime already started
#   - two XDP programs go to one device: the second attach fails with the first attached and
#     pinned, and neither is left on the device
#   - the pin root is off bpffs, on a tmpfs the case mounts above it: the load fails pinning the
#     maps, outside the verifier, and the message is libbpf's, naming the path
#   - a program with no map loads there and attaches, and its link's pin fails: the attached
#     program is off the device, which only the close of an unpinned link takes it off
#   - a run finds a map pinned under a link's name in the root a previous run left: its detach
#     fails, and the run removes the root and exits 1 with the detach's message
#
# Usage: sudo bash tests/luaebpf/undo.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="loader raiser two alone"
trap 'umount "$LUAEBPF_ROOT" 2>/dev/null; cleanup' EXIT

luaebpf_start 7
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_stage loader verdict) || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }
luaebpf_undone "a program the verifier rejects leaves no root, runtime or program" \
	loader 1 'processed [0-9]+ insns' --dev="$LUAEBPF_DEV"

output=$(luaebpf_stage raiser) || { comment "$output"; fail "luaebpf: raiser.bpf.lua did not compile"; }
luaebpf_undone "a kernel script that raises leaves no root, runtime or program" \
	raiser 1 'luaebpf raiser raised on purpose' --dev="$LUAEBPF_DEV"

output=$(luaebpf_stage loader) || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }
luaebpf_undone "a device that does not exist leaves no root, runtime or program" \
	loader 1 "couldn't find device luaebpf-absent" --dev=luaebpf-absent

output=$(luaebpf_stage two) || { comment "$output"; fail "luaebpf: two.bpf.lua did not compile"; }
luaebpf_undone "an attach that fails takes the programs attached before it off the device" \
	two 1 "couldn't attach second" --dev="$LUAEBPF_DEV"

output=$(luaebpf_stage loader) || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }
output=$(luaebpf_stage alone) || { comment "$output"; fail "luaebpf: alone.bpf.lua did not compile"; }
mkdir -p "$LUAEBPF_ROOT" && mount -t tmpfs luaebpf "$LUAEBPF_ROOT" ||
	fail "luaebpf: the case could not mount a tmpfs over $LUAEBPF_ROOT"
luaebpf_undone "a map pin off bpffs fails the load with libbpf's reason and leaves nothing" \
	loader 1 "$LUAEBPF_ROOT/loader/counts is not on BPF FS" --dev="$LUAEBPF_DEV"
luaebpf_undone "a link pin that fails takes the attached program off the device" \
	alone 1 "couldn't pin $LUAEBPF_ROOT/alone/alone-link" --dev="$LUAEBPF_DEV"
umount "$LUAEBPF_ROOT" || fail "luaebpf: the case could not unmount $LUAEBPF_ROOT"

mkdir -p "$LUAEBPF_ROOT/loader"
bpftool map create "$LUAEBPF_ROOT/loader/loader-link" type array key 4 value 4 entries 1 name stale ||
	fail "luaebpf: the case could not pin a map under a link's name"
luaebpf_undone "a stale link pin the run cannot detach removes the root and exits 1" \
	loader 1 "couldn't (open|detach) $LUAEBPF_ROOT/loader/loader-link" --dev="$LUAEBPF_DEV"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

