#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# status and reload name a loaded module whose srcversion is not the installed
# file's, and only a loaded one. A modinfo first on the PATH that answers
# another srcversion stands for another build installed over the loaded one.
#
# - with the modules loaded from the installed build, status exits 0, names the
#   core loaded and no module as another build;
# - against another build, status names each module it reports loaded as not
#   the installed build, and reload loads the modules again and exits 1,
#   couldn't replace, naming the core;
# - with the modules unloaded, status against another build exits 0, names the
#   core not loaded and no module as another build, and unload exits 0 with
#   nothing printed; the modules are loaded again after it.
#
# Usage: sudo bash tests/cli/builds.sh

STALE="is not the installed build"
REFUSAL="loaded from another build"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik load 2>/dev/null
	[ -z "$ANOTHER" ] || rm -rf "$ANOTHER"
}
trap cleanup EXIT
cleanup

ANOTHER=$(mktemp -d)
printf '#!/bin/sh\necho filename: modinfo\necho srcversion: ANOTHER\n' > "$ANOTHER/modinfo"
chmod 755 "$ANOTHER/modinfo"

# the CLI against another build: every srcversion it reads for an installed file is not the loaded one
another() {
	PATH="$ANOTHER:$PATH" cli "$@"
}

# fails unless status exits 0 naming the core as given, and no module as another build
reported() {
	local core="$1"
	shift
	"$@" status
	[ "$status" -eq 0 ] && [ -z "$err" ] && grep -qx "lunatik $core" <<< "$out" && [[ "$out" != *"$STALE"* ]] ||
		fail "status exited $status with '$out' on stdout and '$err' on stderr, not 'lunatik $core'"
}

ktap_header
ktap_plan 4

mark_dmesg

reported "is loaded" cli
ktap_pass "status with the modules loaded from the installed build names the core loaded and no module as another build"

another status
loaded=$(sed -n 's/ is loaded$//p' <<< "$out")
[ "$status" -eq 0 ] && [ -n "$loaded" ] || fail "status against another build exited $status with '$out' and '$err'"
for m in $loaded; do
	grep -qx "$m $STALE" <<< "$out" || fail "status against another build did not name $m: '$out'"
done
another reload
[ "$status" -eq 1 ] && [[ "$err" == "lunatik: couldn't replace "*"lunatik: $REFUSAL" ]] ||
	fail "reload against another build exited $status with '$err' on stderr"
ktap_pass "against another build, status names each loaded module and reload exits 1, couldn't replace"

lunatik unload || fail "the modules did not unload"
reported "is not loaded" another
cli unload
[ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] ||
	fail "unload with the modules unloaded exited $status with '$out' on stdout and '$err' on stderr"
lunatik load || fail "the modules did not load again"
ktap_pass "with the modules unloaded, status names the core not loaded and none as another build, unload exits 0"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

