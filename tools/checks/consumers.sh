#!/bin/bash
# Names the out-of-tree scripts that require a binding the given files change.
# A product built on Lunatik is a consumer this tree cannot grep: point the check
# at the clones with LUNATIK_CONSUMERS, a colon separated list of directories,
# and it reports which of their scripts load what is being changed. Silent when
# the variable is unset, when nothing under lib/ is touched, or when no consumer
# script requires it.
#
# Usage: LUNATIK_CONSUMERS=/path/a:/path/b bash tools/checks/consumers.sh <files...>

[ -n "$LUNATIK_CONSUMERS" ] || exit 0

modules=""
for f in "$@"; do
	case "$f" in
		lib/lua*.c)   modules="$modules $(basename "$f" .c | sed 's/^lua//')" ;;
		lib/*.lua)    modules="$modules $(basename "$f" .lua)" ;;
		lib/*/*.lua)  modules="$modules $(echo "$f" | sed 's|^lib/||; s|\.lua$||')" ;;
	esac
done
[ -n "$modules" ] || exit 0

found=""
for m in $modules; do
	for dir in $(echo "$LUNATIK_CONSUMERS" | tr ':' ' '); do
		[ -d "$dir" ] || continue
		hits=$(grep -rln "require(\"$m\")\|require('$m')" "$dir" --include='*.lua' 2>/dev/null)
		[ -n "$hits" ] && found="$found\n  $m: $(echo $hits | tr '\n' ' ')"
	done
done

[ -n "$found" ] || exit 0
echo "Out-of-tree consumers load a binding this change touches:"
printf "$found\n"
echo "Read them before narrowing what it reports, and say in the pull request what their maintainer must change."

