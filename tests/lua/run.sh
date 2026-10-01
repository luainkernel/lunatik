#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Holds the vendored Lua to the contract the README documents, which the kernel
# patch produces and no other suite asserts: a lost guard compiles and the rest
# of the suite stays green, so a bump of lua/ is read against these.
#
# floats:      no float literal, no '^', integer '/' on constants, registers
#              and coerced strings, no __div or __pow, no libm, no float
#              conversion in string.format or string.pack.
# identifiers: _VERSION, collectgarbage("count") in bytes, package.path, no
#              cpath and require through the kernel symbol table, the io
#              shape, and the entry points a module cannot carry.
# require:     a softirq and a hardirq runtime resumed past their body, the
#              armed state a hook calls from, get back a module the body
#              loaded and are refused a require that would search
#              package.path, and package.searchpath, with "not allowed once
#              the runtime is armed", since opening a file sleeps; the body
#              allows both. The body empties package.path, so a build without
#              the refusal opens no file from the callback and answers "not
#              found" there, as the body's own require does. The body and
#              the callback are refused require("io") with "'io':
#              process-context class in interrupt-context runtime"; without
#              that refusal the body of a module build answers "not found"
#              and that of a built-in one gets io.
#
# Usage: sudo bash tests/lua/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="floats identifiers require"
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

