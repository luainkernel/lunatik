#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The CLI exits by the status the driver replies with: an operation the kernel
# refuses exits 1 with its message on stderr and nothing on stdout, one it
# serves exits 0.
#
# - a run of a script that does not exist exits 1, its error on stderr;
# - a run of idle.lua exits 0 with nothing on stdout or stderr;
# - a second run of it exits 1, already running, on stderr;
# - list exits 0 and names it, and a stop exits 0 and it is gone from list;
# - the REPL prints a value longer than one read of the CLI whole;
# - a reply without a status, which /dev/null bound over /dev/lunatik in a mount
#   namespace of its own stands for, fails -e, -V, load and unload with exit 1,
#   couldn't read, and nothing on stdout, and the unload removes no module.
#
# Usage: sudo bash tests/control/status.sh

SCRIPT="tests/control/idle"
MISSING="tests/control/missing"
LONG=10000
DEVICE="/dev/lunatik"
REFUSAL="couldn't read $DEVICE: loaded from another build"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik load 2>/dev/null
	[ -z "$ANOTHER" ] || rm -rf "$ANOTHER"
}
trap cleanup EXIT
cleanup

ANOTHER=$(mktemp -d)
cat > "$ANOTHER/lunatik" <<END
#!/bin/sh
exec unshare --mount sh -c 'mount --bind /dev/null $DEVICE && exec "\$0" "\$@"' "$(command -v lunatik)" "\$@"
END
chmod 755 "$ANOTHER/lunatik"

# the CLI against a driver that replies without a status
another() {
	PATH="$ANOTHER:$PATH" cli "$@"
}

ktap_header
ktap_plan 7

mark_dmesg

cli run "$MISSING"
[ "$status" -eq 1 ] && [ -z "$out" ] && [ -n "$err" ] ||
	fail "a run of a missing script exited $status with '$out' on stdout and '$err' on stderr"
ktap_pass "a run of a script that does not exist exits 1 with its error on stderr"

cli run "$SCRIPT"
[ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] ||
	fail "a run exited $status with '$out' on stdout and '$err' on stderr"
ktap_pass "a run exits 0 with nothing on stdout or stderr"

cli run "$SCRIPT"
[ "$status" -eq 1 ] && [ -z "$out" ] && [[ "$err" == *"already running"* ]] ||
	fail "a second run exited $status with '$out' on stdout and '$err' on stderr"
ktap_pass "a second run of a running script exits 1, already running, on stderr"

cli list
[ "$status" -eq 0 ] && [[ "$out" == *"$SCRIPT"* ]] || fail "list exited $status with '$out'"
cli stop "$SCRIPT"
[ "$status" -eq 0 ] || fail "a stop exited $status with '$err'"
cli list
[[ "$out" != *"$SCRIPT"* ]] || fail "a stopped script is still listed: '$out'"
ktap_pass "list exits 0 and names a running script, and a stop exits 0 and removes it"

# readline echoes a piped line to stdout, so the chunk spells its x as \120
value=$(printf 'string.rep("\\120", %d)\n' "$LONG" | lunatik | tr -cd x)
[ "${#value}" -eq "$LONG" ] || fail "a value of $LONG bytes reached the REPL as ${#value}"
ktap_pass "the REPL prints a value longer than one read whole"

loaded=$(ls /sys/module/lunatik/holders)
for args in "-e return" "-V" "load" "unload"; do
	another $args
	[ "$status" -eq 1 ] && [ -z "$out" ] && [ "$err" = "lunatik: $REFUSAL" ] ||
		fail "lunatik $args against a reply without a status exited $status with '$out' on stdout and '$err' on stderr"
done
for m in $loaded; do
	[ -d "/sys/module/$m" ] || fail "an unload against a reply without a status removed $m"
done
ktap_pass "a reply without a status fails -e, -V, load and unload, couldn't read, and the unload removes no module"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

