#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the license a program file names in the options of its constructors, which the object's
# license section carries and the kernel reads for whether a program is GPL-compatible. The case
# writes each program file, its programs calling nothing unless a row says they call the runtime.
#   - an XDP and a TC program that both name GPL compile into an object whose license section reads
#     GPL, and bpftool reads both loaded GPL-compatible
#   - an XDP and a TC program that both name Proprietary, a license license_is_gpl_compatible does
#     not count, load, and bpftool reads neither GPL-compatible; `lunatik run` attaches an XDP
#     program and a TC one under it, the TC one by tcx
#   - an XDP program under Proprietary that may stop, dividing by zero, compiles, and the kernel
#     refuses to load it with the verifier's "cannot call GPL-restricted function from non-GPL
#     compatible program", since its stop logs through bpf_trace_printk
#   - an XDP and a TC program under Proprietary that call the runtime compile, and the `lunatik run`
#     of each exits 1 with the verifier's "cannot call kernel function from non-GPL compatible
#     program" and leaves nothing behind. Each skips where the kernel publishes no BTF for the
#     module whose kfunc its program calls
#   - the TC rows of `lunatik run` skip where the CLI's loader names a libbpf older than tcx
#   - a constructor whose license is not the one of the programs before it is refused at the line
#     of its function: two programs naming two licenses, one naming GPL after one naming none, and
#     one naming none, whose license is Dual MIT/GPL, after one naming GPL
#   - a license that is not a string, a number to xdp.program and false to tc.program, is refused
#     at the line of its function
# pass.sh covers a file that names no license.
#
# Usage: sudo bash tests/luaebpf/license.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="xdpattached tcattached xdpcalls tccalls"
trap cleanup EXIT

RUNTIME=tests/luaebpf/words
OTHER=Proprietary
REFUSED="cannot call kernel function from non-GPL compatible program" # add_kfunc_call, kernel/bpf/verifier.c
GPLONLY="cannot call GPL-restricted function from non-GPL compatible program" # check_helper_call
NOTCX="tcx needs libbpf 1.3.0" # lualoader_open, luaebpf/loader.c

luaebpf_start 12
command -v readelf >/dev/null || skip_script "luaebpf: readelf is not installed"
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

# program <kind> <name> <license> [calls|stops]: a program of <kind>, xdp or tc, named <name>, under
# <license>, a Lua expression, or none where it is '-', whose function calls the runtime where
# `calls` follows and divides by zero where `stops` does; four lines where it does neither
program() {
	local kind="$1" name="$2" license="$3" verdict=xdpaction.PASS
	[ "$kind" = tc ] && verdict=tcaction.OK
	[ "$license" = - ] && license=
	echo "$kind.program(function(_)"
	[ "${4:-}" = calls ] && echo $'\tlocal v = words:run()\n\tif v then\n\t\treturn v\n\tend'
	[ "${4:-}" = stops ] && echo $'\tlocal v = 1 // 0'
	echo $'\t'"return $verdict"
	echo "end, {name = \"$name\", default = $verdict${license:+, license = $license}})"
	echo
}

# programs <name> <program>...: <name>.bpf.lua in the scratch directory, seven lines of header and
# then each <program>, the arguments program() takes in one word, so the function of a second
# program that follows one calling nothing is defined at line 12
programs() {
	local name="$1" spec
	shift
	{
		echo 'local xdp       = require("bpf.xdp")'
		echo 'local tc        = require("bpf.tc")'
		echo 'local lunatik   = require("lunatik")'
		echo 'local xdpaction = require("linux.xdp").action'
		echo 'local tcaction  = require("linux.tc").action'
		echo "local words     = lunatik.runtime(\"$RUNTIME\")"
		echo
		for spec in "$@"; do
			# shellcheck disable=SC2086 # a spec is the words of one program
			program $spec
		done
	} > "$LUAEBPF_WORK/$name.bpf.lua"
}

# row <title> <check> [<argument>...]: a case <check> passes by exiting 0, and fails with what it
# printed
row() {
	local title="$1" output
	shift
	if output=$("$@" 2>&1); then
		ktap_pass "luaebpf: $title"
	else
		comment "$output"
		ktap_fail "luaebpf: $title"
	fi
}

# whether bpftool reads the program <selector> names as GPL-compatible, true or false
gpl() {
	bpftool -j prog show "$@" | grep -oP '"gpl_compatible":\K[a-z]+'
}

# loaded <name> <license> <gpl>: <name>.bpf.lua compiles into an object whose license section holds
# <license> and its terminator, and its programs, <name>xdp and <name>tc, load GPL-compatible where
# <gpl> is true
loaded() {
	local name="$1" license="$2" expected="$3" got size program
	luaebpf_written "$name" || return 1
	got=$(readelf -p license "$LUAEBPF_WORK/$name.bpf.o" | sed -n 's/^ *\[ *0\]  //p')
	[ "$got" = "$license" ] || { echo "the license section holds '$got'"; return 1; }
	size=$(readelf -S -W "$LUAEBPF_WORK/$name.bpf.o" | sed 's/^ *\[ *[0-9]*\] //' \
		| awk '$1 == "license" { print $5 }')
	[ $((16#${size:-0})) -eq $((${#license} + 1)) ] || { echo "the license section is 0x$size bytes"; return 1; }
	luaebpf_loadall "$name" || return 1
	got=$(for program in "${name}xdp" "${name}tc"; do gpl pinned "$LUAEBPF_PINS/$program"; done | tr '\n' ' ')
	rm -f "$LUAEBPF_PINS/${name}xdp" "$LUAEBPF_PINS/${name}tc"
	[ "$got" = "$expected $expected " ] || { echo "the programs loaded with gpl_compatible '$got'"; return 1; }
}

# unloaded <name> <reason>: <name>.bpf.lua compiles, and the kernel refuses to load its object,
# whose one program the file names <name>, with <reason>
unloaded() {
	local name="$1" output status
	luaebpf_written "$name" || return 1
	output=$(luaebpf_loadall "$name")
	status=$?
	rm -f "$LUAEBPF_PINS/$name"
	[ "$status" -ne 0 ] || { echo "the object loaded"; return 1; }
	grep -qF "$2" <<< "$output" || { echo "$output"; return 1; }
}

# staged <name>: <name>.bpf.lua compiled where `lunatik run` looks for tests/luaebpf/<name>'s object
staged() {
	luaebpf_written "$1" && mkdir -p "$LUAEBPF_OBJECTS" && cp "$LUAEBPF_WORK/$1.bpf.o" "$LUAEBPF_OBJECTS/"
}

# attached <name>: `lunatik run` attaches the program of <name>.bpf.lua, which the kernel did not load
# GPL-compatible
attached() {
	local name="$1" output status id got
	staged "$name" || return 1
	output=$(lunatik run --dev="$LUAEBPF_DEV" "tests/luaebpf/$name" 2>&1)
	status=$?
	id=$(luaebpf_attached)
	got=$([ -n "$id" ] && gpl id "$id")
	lunatik stop "tests/luaebpf/$name" > /dev/null 2>&1
	[ "$status" -eq 0 ] && [ -z "$output" ] || { echo "the run exited $status: $output"; return 1; }
	[ -n "$id" ] || { echo "$LUAEBPF_DEV carries no program"; return 1; }
	[ "$got" = false ] || { echo "the attached program loaded with gpl_compatible '$got'"; return 1; }
}

programs gpl 'xdp gplxdp "GPL"' 'tc gpltc "GPL"'
row "an XDP and a TC program naming GPL compile under it and load GPL-compatible" loaded gpl GPL true

programs other "xdp otherxdp \"$OTHER\"" "tc othertc \"$OTHER\""
row "an XDP and a TC program naming $OTHER load, and neither is GPL-compatible" loaded other "$OTHER" false

programs otherstops "xdp otherstops \"$OTHER\" stops"
row "an XDP program naming $OTHER that may stop is refused at load with the reason" unloaded otherstops "$GPLONLY"

programs xdpattached "xdp xdpattached \"$OTHER\""
row "lunatik run attaches an XDP program naming $OTHER" attached xdpattached

title="lunatik run attaches a TC program naming $OTHER"
programs tcattached "tc tcattached \"$OTHER\""
notcx=
if output=$(attached tcattached 2>&1); then
	ktap_pass "luaebpf: $title"
elif grep -qF "$NOTCX" <<< "$output"; then
	notcx=$NOTCX
	ktap_skip "luaebpf: $title ($NOTCX)"
else
	comment "$output"
	ktap_fail "luaebpf: $title"
fi

# calls <kind> <reason> <program>: the row of <program>, of <kind>, naming $OTHER and calling the
# runtime, whose run exits 1 with the verifier's sentence and leaves nothing, skipped where <reason>
# is not empty
calls() {
	local kind="$1" reason="$2" output
	local title="$3 naming $OTHER that calls the runtime is refused at load with the reason, leaving nothing"
	programs "${kind}calls" "$kind ${kind}calls \"$OTHER\" calls"
	if [ -n "$reason" ]; then
		ktap_skip "luaebpf: $reason"
	elif output=$(staged "${kind}calls" 2>&1); then
		luaebpf_undone "$title" "${kind}calls" 1 "$REFUSED" --dev="$LUAEBPF_DEV"
	else
		comment "$output"
		ktap_fail "luaebpf: $title"
	fi
}

calls xdp "$(luaebpf_kfunc luaxdp)" "an XDP program"
calls tc "${notcx:-$(luaebpf_kfunc luatc)}" "a TC program"

BEFORE="the license of the programs before it"
programs twonames 'xdp first "GPL"' "tc second \"$OTHER\""
luaebpf_refused twonames "twonames.bpf.lua:12: tc.program's license '$OTHER' is not 'GPL', $BEFORE"
programs namedafter 'xdp first -' 'tc second "GPL"'
luaebpf_refused namedafter "namedafter.bpf.lua:12: tc.program's license 'GPL' is not 'Dual MIT/GPL', $BEFORE"
programs noneafter 'xdp first "GPL"' 'xdp second -'
luaebpf_refused noneafter "noneafter.bpf.lua:12: xdp.program's license 'Dual MIT/GPL' is not 'GPL', $BEFORE"

programs number 'xdp number 2'
luaebpf_refused number "number.bpf.lua:8: xdp.program's license is not a string"
programs boolean 'tc boolean false'
luaebpf_refused boolean "boolean.bpf.lua:8: tc.program's license is not a string"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

