#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the directory `lunatik bpf --scripts` names, from which a program file's body requires the
# kernel scripts in place of /lib/modules/lua. The body writes where its class came from beside the
# object.
#   - a directory laid out as /lib/modules/lua, named relative to where the compile runs, whose
#     linux/xdp.lua gives PASS a value no kernel gives it and whose class is a class/init.lua of its
#     own: the body's class is that file, and the program, which returns the action.PASS the body
#     read, returns that value
#   - luaebpf.compile, called in one process for /lib/modules/lua, then for a directory whose
#     linux/xdp.lua gives PASS another value and which lacks class, which raises, and then for the
#     first directory, named by its absolute path, reads that directory the third time and writes
#     the object lunatik bpf --scripts wrote: the modules an earlier body loaded, the one that raised
#     included, are not the next one's
#   - a module the directory lacks, class, is not found: the message names the directory's paths and
#     none under /lib/modules/lua, which holds one, and no object is written
#   - the compile without --scripts reads /lib/modules/lua, --scripts on a copy of it reads the
#     copy, and the two write the same object
#
# Usage: sudo bash tests/luaebpf/scripts.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

SCRIPTS=/lib/modules/lua
SENTINEL=7 # PASS in no kernel's linux.xdp

trap cleanup EXIT

luaebpf_start 4

# compile <object> [<option>...]: scripts.bpf.lua compiled into <object> with the options given
compile() {
	local object="$1"
	shift
	( cd "$LUAEBPF_WORK" && lunatik bpf "$@" -o "$object" "$LUAEBPF_SRC/scripts.bpf.lua" ) 2>&1
}

# the source of the class the last compile's body required
found() {
	cat "$LUAEBPF_WORK/class.txt"
}

dir="$LUAEBPF_WORK/scripts"
mkdir -p "$dir/linux" "$dir/class" || fail "luaebpf: the scripts directory could not be made"
echo "return {action = {PASS = $SENTINEL}}" > "$dir/linux/xdp.lua"
echo 'return function() end' > "$dir/class/init.lua"
broken="$LUAEBPF_WORK/broken"
mkdir -p "$broken/linux" || fail "luaebpf: the directory lacking class could not be made"
echo "return {action = {PASS = $((SENTINEL + 1))}}" > "$broken/linux/xdp.lua"

output=$(compile "$LUAEBPF_WORK/scripts.bpf.o" --scripts=scripts) \
	|| { comment "$output"; fail "luaebpf: scripts.bpf.lua did not compile through --scripts"; }
[ "$(found)" = "@scripts/class/init.lua" ] || fail "luaebpf: class is read from $(found), not $dir"
output=$(luaebpf_loadall scripts) || { comment "$output"; fail "luaebpf: the object did not load"; }
verdict=$(luaebpf_verdict scripts)
[ "$verdict" = "$SENTINEL" ] || fail "luaebpf: the program returned '$verdict', not the PASS $dir gives"
ktap_pass "luaebpf: the body requires the kernel scripts from the directory --scripts names"

output=$(cd "$LUAEBPF_WORK" && lua5.5 - "$LUAEBPF_SRC/scripts.bpf.lua" "$dir" "$broken" \
	"$LUAEBPF_WORK/again.bpf.o" 2>&1 <<'LUA'
local luaebpf = require("luaebpf")

local program, scripts, broken, object = table.unpack(arg)
luaebpf.compile(program)
local ok, err = pcall(luaebpf.compile, program, nil, broken)
assert(not ok and err:find("module 'class' not found", 1, true),
	"the compile of a directory lacking class gave: " .. tostring(err))
local file = assert(io.open(object, "wb"))
assert(file:write(luaebpf.compile(program, nil, scripts)))
assert(file:close())
LUA
) || { comment "$output"; fail "luaebpf: scripts.bpf.lua did not compile again in one process"; }
[ "$(found)" = "@$dir/class/init.lua" ] \
	|| fail "luaebpf: the third compile in one process reads class from $(found), not $dir"
cmp -s "$LUAEBPF_WORK/again.bpf.o" "$LUAEBPF_WORK/scripts.bpf.o" \
	|| fail "luaebpf: the third compile in one process writes another object than lunatik bpf --scripts"
ktap_pass "luaebpf: a compile reads its own kernel scripts, not those an earlier compile in its process loaded"

rm -r "$dir/class"
output=$(compile "$LUAEBPF_WORK/missing.bpf.o" --scripts="$dir")
[ $? -ne 0 ] && grep -qF "module 'class' not found" <<< "$output" \
	&& grep -qF "no file '$dir/class.lua'" <<< "$output" && ! grep -qF "$SCRIPTS/" <<< "$output" \
	&& [ ! -e "$LUAEBPF_WORK/missing.bpf.o" ] \
	|| { comment "$output"; fail "luaebpf: a module the --scripts directory lacks is read elsewhere"; }
ktap_pass "luaebpf: a module the --scripts directory lacks is not found, and $SCRIPTS is not read"

output=$(compile "$LUAEBPF_WORK/default.bpf.o") \
	|| { comment "$output"; fail "luaebpf: scripts.bpf.lua did not compile"; }
[ "$(found)" = "@$SCRIPTS/class.lua" ] || fail "luaebpf: class is read from $(found), not $SCRIPTS"
cp -r "$SCRIPTS" "$LUAEBPF_WORK/copy" || fail "luaebpf: $SCRIPTS could not be copied"
output=$(compile "$LUAEBPF_WORK/copy.bpf.o" --scripts="$LUAEBPF_WORK/copy") \
	|| { comment "$output"; fail "luaebpf: scripts.bpf.lua did not compile through --scripts on a copy"; }
[ "$(found)" = "@$LUAEBPF_WORK/copy/class.lua" ] || fail "luaebpf: class is read from $(found), not the copy"
cmp -s "$LUAEBPF_WORK/copy.bpf.o" "$LUAEBPF_WORK/default.bpf.o" \
	|| fail "luaebpf: --scripts on a copy of $SCRIPTS writes another object"
ktap_pass "luaebpf: --scripts on a copy of $SCRIPTS reads the copy and writes the object $SCRIPTS gives"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

