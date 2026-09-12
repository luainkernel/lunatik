#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Everything that is not a deliberate denial allows.
#
# A callback that forgets to return has to allow, or the first rule anyone
# writes wrong takes a machine's files away. The other three answers are the
# ones the kernel could not use: security_file_open's caller turns a non-zero
# return into an error pointer and dereferences it, so a 1 or a -1000000 arrives
# as a value IS_ERR does not recognise, and a string arrives as no number at
# all. Three more pin how the answer is read: math.maxinteger, whose low 32 bits
# are -1; the string "-1", which lua_tointeger would take as one; and -4096, the
# first value past the errno range. Each file carries its answer's name, and
# each is read while its answer is in force; the callback's line has to be there
# too, or a mark that never fired would pass every case.
#
# Usage: sudo bash tests/fsnotify/default.sh

SCRIPT="tests/fsnotify/default"
ANSWERS="nothing positive text huge wide numeral beyond"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/perm.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$PROBE" 2>/dev/null
	umount "$MOUNT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

perm_begin 8 "fsnotify/default"

for answer in $ANSWERS; do echo "$answer" > "$MOUNT/$answer"; done

run_script "$SCRIPT"

reads=()
seen=()
for answer in $ANSWERS; do
	mark_dmesg
	reads+=("$(cat "$MOUNT/$answer" 2>&1)")
	seen+=("$(dmesg_since)")
done
lunatik stop "$SCRIPT" 2>/dev/null

i=0
for answer in $ANSWERS; do
	content=${reads[i]}
	output=${seen[i]}
	i=$((i + 1))

	[ "$content" = "$answer" ] || fail "a callback returning '$answer' denied the open: $content"
	echo "$output" | grep -qF "default test: $answer mask 10000" || \
		fail "the callback did not see the open of $answer: $(echo "$output" | grep -F 'fsnotify default test')"
	ktap_pass "a callback returning $answer allows"
done

errs=$(printf '%s\n' "${seen[@]}" | grep -E "\.lua:[0-9]+:" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

