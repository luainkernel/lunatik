#!/usr/bin/env bash
# A guard in the core is for the honest mistake, and a script that reaches into the runtime's own
# bookkeeping, the registry, a class metatable or an object's __gc, is out of contract (AGENTS.md,
# "Deciding what to change"): a finding whose stimulus is such a script closes as not a defect.
# #1067 and #1106 were filed with that stimulus and answered with a pull request each before the
# family was read as one. Takes text files, a finding about to be filed; prints each line that
# names such a stimulus and exits 1, silent otherwise.

stimulus='debug\.(getregistry|setmetatable)\b|getmetatable\([^)]*\)\.__gc\b|[:.]__gc\('

status=0
for file in "$@"; do
	hits=$(grep -nE "$stimulus" "$file")
	[ -z "$hits" ] && continue
	printf '%s\n' "$hits" | sed "s|^|$file:|"
	echo "$file: the stimulus reaches into the runtime's own bookkeeping, which is out of contract (AGENTS.md, a guard in the core is for the honest mistake); close it as not a defect, or pass CONTRACT_OK=1 where a script using the API as documented reaches the same path"
	status=1
done
exit $status

