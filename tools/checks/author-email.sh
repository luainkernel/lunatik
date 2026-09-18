#!/usr/bin/env bash
# Names a commit whose author email is not the one the base uses most for that author's
# name: a rebase or a squash done from another checkout signs the result with that
# checkout's git identity, and #850 reached its review under an address the history knows
# from three commits against several hundred. Takes a rev-range whose left side is the base
# (origin/master..HEAD); silent when every commit matches, and on an author the base has
# never seen.

range=${1:?usage: $0 <base>..<head>}
base=${range%%..*}

git rev-list "$range" | while read -r commit; do
	name=$(git log -1 --format=%an "$commit")
	email=$(git log -1 --format=%ae "$commit")
	known=$(git log --format=%ae --fixed-strings --author="$name <" "$base" | sort | uniq -c | sort -rn | awk 'NR == 1 {print $2}')
	[ -n "$known" ] && [ "$known" != "$email" ] || continue
	echo "$(git log -1 --format='%h "%s"' "$commit"): $name <$email>; $base has $name <$known>"
done

