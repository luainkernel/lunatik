#!/usr/bin/env bash
# A failure that comes and goes is read in the journal and named by its mechanism, or carried
# as a hypothesis; "flake" is the word for a symptom nobody read, and a review that used it for
# tests/netlink/nl80211_station passed over NetworkManager taking the test's interface (#1010).
# Takes text files, a review body, a comment, a pull request body or a hand-back; prints each
# line that names a failure that way and exits 1, silent otherwise.

status=0
for file in "$@"; do
	hits=$(grep -niE '\bflak(e|y|es|ed|iness)\b' "$file")
	[ -z "$hits" ] && continue
	printf '%s\n' "$hits" | sed "s|^|$file:|"
	echo "$file: names a failure as a flake; read the journal around the failing run (tools/journal.sh) and name the mechanism, or write it as a hypothesis with what was not captured"
	status=1
done
exit $status

