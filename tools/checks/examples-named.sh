#!/usr/bin/env bash
# A pull request whose change touches a binding says, in its body, what each example that uses the
# binding did: ran, only loaded, or was not run and why (AGENTS.md, "Before opening a pull request",
# item 6). tools/checks/examples-touched.sh lists them from the changed files; #1140 changed the
# netdevice callback's contract with a body that named one of the three the list carried, and the
# two it left, linkflap and netfailover, acted on a homonym from another namespace until the review
# ran them. Takes the body file and the changed files; prints each example the list carries that
# the body does not name and exits 1, silent otherwise. An example is named by its directory or
# file name under examples/, as the list prints it.
# Usage: examples-named.sh <body> <changed file>...

body=$1
shift
[ -f "$body" ] || { echo "examples-named: no body file at $body"; exit 2; }

listed=$(bash "$(dirname "$0")/examples-touched.sh" "$@" 2> /dev/null |
	grep -oE 'examples/[A-Za-z0-9_.-]+' | sed 's|^examples/||; s|\.lua$||' | sort -u)
[ -z "$listed" ] && exit 0

status=0
for example in $listed; do
	grep -qw -- "$example" "$body" && continue
	echo "$body: examples/$example uses a binding the change touches, and the body does not say whether it ran"
	status=1
done
exit $status

