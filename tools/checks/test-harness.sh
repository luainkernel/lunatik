#!/bin/bash
# Checks a test script under tests/ for what it cannot detect: a script run with
# `lunatik run` whose failure to load nothing reads, neither the exit status nor
# the output, so a broken require reports as a pass, a dmesg check alone included;
# a skip on srcversion alone, which proves the loaded
# module is the installed file and not that the file carries the fix, the way
# tests/runtime/self_stop first skipped; and a message the header says
# check_dmesg reads that tests/lib.sh's KTAP_ERRORS does not match, the BUG line
# tests/rcu/entry_release first claimed. Heuristic: it nudges a review, it does
# not rewrite.
# Usage: test-harness.sh <file>...
# Prints the findings; exits 1 when there are any. Files outside its scope
# are skipped silently, so callers can pass any path.

rc=0

check() {
	local file="$1" issues=""

	case "$file" in
		*/lib.sh|*/run.sh|lib.sh|run.sh) return 0 ;; # the library and the runners, not tests
		*/tests/*.sh|tests/*.sh) ;;
		*) return 0 ;;
	esac
	[ -f "$file" ] || return 0

	add() { issues="${issues}- $1
"; }

	# covered when the script uses run_script/run_test (tests/lib.sh, which fail
	# on any output), when it tests the output captured with 2>&1 for emptiness,
	# when it asserts the output it expects (grep ... || fail), or when it reads the
	# exit status of the run: each notices a script that failed to load. Matching
	# `file.lua:N:` on top of that is fine, as a dmesg signal; what it cannot do is
	# stand alone.
	if grep -q 'lunatik run' "$file" &&
		! grep -qE '\brun_script\b|\brun_test\b' "$file" &&
		! grep -qE 'lunatik run[^|&#]*(\|\||&&)|if !? *lunatik run' "$file" &&
		! { grep -qE '\[ -[nz] "\$\{?out' "$file" && grep -qE 'lunatik run.*2>&1' "$file"; } &&
		! grep -qE 'grep -q[a-zA-Z]*[[:space:]].*\|\|' "$file"; then
		if grep -qE 'grep -[a-zA-Z]*E?[a-zA-Z]*[[:space:]]*"?.\\\.lua:\[0-9\]' "$file"; then
			add "detects errors by matching \`file.lua:N:\`, which a failed require does not print; check the exit status or any output instead"
		else
			add "runs a script without checking whether it loaded, so a failed load reports a pass. Check the exit status (lunatik run ... || fail), capture the output (2>&1) and treat any as a failure, or use run_script/run_test from tests/lib.sh"
		fi
	fi

	# a skip that compares srcversion proves that the loaded module is the installed file, not that
	# the file carries the fix: a checkout ahead of its install then runs the case against the old
	# module. The proof is a symbol only the fixed build has in /proc/kallsyms, or the message of an
	# inline check read from the module file (grep -aF ... "$(modinfo -n <module>)").
	if grep -q 'srcversion' "$file" && ! grep -qE 'kallsyms|modinfo -n' "$file"; then
		add "skips on srcversion alone, which proves that the loaded module is the installed one and not that the file carries the fix; read a symbol in /proc/kallsyms or the message in \$(modinfo -n <module>) as well"
	fi

	# a message the header says check_dmesg reads is one tests/lib.sh's KTAP_ERRORS matches
	local lib pattern token
	lib=$(dirname "$file")/../lib.sh
	[ -f "$lib" ] || lib=$(dirname "$(readlink -f "$0")")/../../tests/lib.sh
	pattern=$(sed -n "s/^KTAP_ERRORS='\(.*\)'$/\1/p" "$lib" 2> /dev/null)
	if [ -n "$pattern" ]; then
		while read -r token; do
			[ -n "$token" ] || continue
			printf '%s:\n' "$token" | grep -qE "$pattern" ||
				add "says check_dmesg reads \`$token\`, which KTAP_ERRORS in tests/lib.sh does not match: the case proves nothing by it"
		done <<< "$(grep -E '^#.*check_dmesg' "$file" | grep -oE '\bBUG\b|\bWARNING\b|\bUBSAN\b|Internal error|\boops\b|Unexpected kernel BRK' | sort -u)"
	fi

	[ -z "$issues" ] && return 0
	printf '%s may not detect what it says it does:\n%sSee tests/lib.sh (run_script/run_test, KTAP_ERRORS) and tests/bpf/run.sh for the expected shape.\n' \
		"$(basename "$file")" "$issues"
	return 1
}

for f in "$@"; do
	check "$f" || rc=1
done
exit $rc

