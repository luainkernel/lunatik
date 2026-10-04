#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Holds the vendored Lua to the contract the README documents, which the kernel
# patch produces and no other suite asserts: a lost guard compiles and the rest
# of the suite stays green, so a bump of lua/ is read against these. util holds
# the util module to its documentation on that Lua's stack.
#
# floats:      no float literal, no '^', integer '/' on constants, registers
#              and coerced strings, no __div or __pow, no libm, no float
#              conversion in string.format or string.pack.
# identifiers: _VERSION, collectgarbage("count") in bytes, package.path, no
#              cpath and require through the kernel symbol table, the io
#              shape, and the entry points a module cannot carry.
# require:     a require finds a binding before a Lua file of its name,
#              device.lua in this directory. A softirq and a hardirq runtime
#              resumed past their body, the armed state a hook calls from,
#              get back a module the body loaded and are refused, with "not
#              allowed once the runtime is armed", a require of a binding or
#              of a Lua library the body did not load, package.loadlib and
#              package.searchpath, since opening a file sleeps and loading a
#              binding takes a module reference an atomic allocation can
#              leak; the body allows them. The body empties package.path, so a
#              build without the refusal opens no file from the callback and
#              answers "not found" there, as the body's own require does. The
#              body and the callback are refused require("io") with "'io':
#              process-context class in interrupt-context runtime"; without
#              that refusal the body of a module build answers "not found"
#              and that of a built-in one gets io. The callback's loadfile
#              returns the armed refusal and its dofile raises it; both are
#              called without a name, which the body answers with "cannot
#              open" and for which a build without the refusal opens no file
#              either.
# loadfile:    loadfile, dofile and require of a directory, which the kernel
#              opens and refuses to read, answer the errno's name, EINVAL,
#              as a failed kernel call raises it; for a path the kernel does
#              not open, loadfile returns, and dofile raises, "cannot open
#              <file>: " and the errno's name, ENOENT for a missing file and
#              ENOTDIR for one under a regular file.
# patterns:    a pattern nests at most 32 levels: 31 optional items match in
#              string.find, match, gmatch and gsub, and 32 raise "pattern too
#              complex" in each; 15 captures and an optional item match and
#              16 captures raise, a capture taking two levels. A build without
#              the bound recurses 33 levels, harmlessly, and matches.
# util:        bin2hex encodes every byte value in a string of 2048 bytes,
#              past the 200 slots of LUAI_MAXSTACK, and hex2bin decodes it back
#              from either case; each returns the string alone, the empty string
#              included, and hex2bin refuses an odd length and a character that
#              is not a hexadecimal digit with "invalid hexadecimal string".
#
# Usage: sudo bash tests/lua/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="floats identifiers require loadfile patterns util"
TOTAL=$(echo $TESTS | wc -w)

cleanup()
{
	for t in $TESTS; do
		lunatik stop "tests/lua/$t" > /dev/null 2>&1
	done
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if run_test "tests/lua/$t"; then
		ktap_pass "lua/$t"
	else
		ktap_fail "lua/$t"
	fi
done

ktap_totals

