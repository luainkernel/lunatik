#!/bin/bash
# Checks a test script under tests/ for the exit-status blind spot: a script
# that fails to load reports on the output of `lunatik run`, which exits 0 in
# that case, so an exit-status or dmesg check alone reports a broken require
# as a pass. Heuristic: it nudges a review, it does not rewrite.
# Usage: test-harness.sh <file>...
# Prints the findings; exits 1 when there are any. Files outside its scope
# are skipped silently, so callers can pass any path.

rc=0

check() {
	local file="$1" issues=""

	case "$file" in
		*/tests/*.sh|tests/*.sh) ;;
		*) return 0 ;;
	esac
	[ -f "$file" ] || return 0

	grep -q 'lunatik run' "$file" || return 0

	add() { issues="${issues}- $1
"; }

	# covered when the script uses run_script/run_test (tests/lib.sh, which fail
	# on any output), when it tests the captured output for emptiness, or when it
	# asserts the output it expects (grep ... || fail): all three notice a script
	# that printed a loader error instead of running. Matching `file.lua:N:` on
	# top of that is fine, as a dmesg signal; what it cannot do is stand alone.
	if ! grep -qE '\brun_script\b|\brun_test\b' "$file" &&
		! grep -qE '\[ -[nz] "\$\{?out' "$file" &&
		! grep -qE 'grep -q[a-zA-Z]*[[:space:]].*\|\|' "$file"; then
		if grep -qE 'grep -[a-zA-Z]*E?[a-zA-Z]*[[:space:]]*"?.\\\.lua:\[0-9\]' "$file"; then
			add "detects errors by matching \`file.lua:N:\`, which a failed require does not print; check for any output instead"
		else
			add "runs a script without checking its output: \`lunatik run\` exits 0 when the script fails to load, so this reports a pass. Capture the output (2>&1) and treat any output as a failure, or use run_script/run_test from tests/lib.sh"
		fi
	fi

	[ -z "$issues" ] && return 0
	printf '%s may not detect a script that never ran:\n%sSee tests/lib.sh (run_script/run_test) and tests/bpf/run.sh for the expected shape.\n' \
		"$(basename "$file")" "$issues"
	return 1
}

for f in "$@"; do
	check "$f" || rc=1
done
exit $rc

