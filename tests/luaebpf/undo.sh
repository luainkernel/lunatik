#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that a `lunatik run` failing at any step of the load leaves nothing behind: no pin root,
# no registered runtime and nothing on the device. One row per step, each with the stimulus that
# fails it.
#   - the verifier rejects the program, after libbpf has already created and pinned the maps, so
#     the undo is the loader's own rather than a side effect of the failure
#   - the kernel script raises, with the object loaded and its maps pinned
#   - the device the command line named does not exist, so the attach fails before the first link
#   - two XDP programs go to one device: the second attach fails with the first already attached
#     and pinned, and neither is left live
#
# Usage: sudo bash tests/luaebpf/undo.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 4
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_install loader verdict)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }
luaebpf_undone "a program the verifier rejects leaves no root, runtime or attachment" \
	loader 'processed [0-9]+ insns' dev="$LUAEBPF_DEV"

output=$(luaebpf_install raiser)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: raiser.bpf.lua did not compile"; }
luaebpf_undone "a kernel script that raises leaves no root, runtime or attachment" \
	raiser 'luaebpf raiser raised on purpose' dev="$LUAEBPF_DEV"

output=$(luaebpf_install loader)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }
luaebpf_undone "a device that does not exist leaves no root, runtime or attachment" \
	loader "couldn't find device 'luaebpf-absent'" dev=luaebpf-absent

output=$(luaebpf_install two)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: two.bpf.lua did not compile"; }
luaebpf_undone "an attach that fails takes the links before it off the device" \
	two "couldn't attach 'second'" dev="$LUAEBPF_DEV"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

