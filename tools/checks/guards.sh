# Sourced by guard-removed.sh and crash-guard.sh: the lines that carry a crash guard, and
# the ones a tree drops against HEAD. A guard that only moved, into a helper or onto another
# index, is paired with the added line that took it in and not reported: #850's review moved
# an argcheck two methods shared into one helper and both guards read as dropped.

guards='lunatik_argcheckclass|lunatik_argchecknull|lunatik_checkobject|lunatik_checkpobject|LUNATIK_PRIVATECHECKER'
guards="$guards|luaL_argcheck|luaL_argexpected|luaL_checktype|luaL_checkudata|lunatik_checkruntime"
guards="$guards|lunatik_checkpercpu|lunatik_checkcontext|lunatik_checkclass|lunatik_cannotsleep"

# the guard as a shape: the index it reads and the spacing around it are not the guard
guard_shape() {
	sed -E 's/^[-+][[:space:]]*//; s/[[:space:]]+/ /g; s/, (ix|idx|[0-9]+)([,)])/, N\2/g'
}

# the guard lines <tree> drops against HEAD under <paths>, minus those an added line took in
dropped_guards() {
	local tree=$1
	shift
	local diff added line shape
	diff=$(git -C "$tree" diff HEAD -U0 -- "$@" 2>/dev/null | grep -E '^[-+][^-+]' | grep -E "$guards")
	added=$(printf '%s\n' "$diff" | grep -E '^\+' | guard_shape)
	printf '%s\n' "$diff" | grep -E '^-' | while IFS= read -r line; do
		shape=$(printf '%s\n' "$line" | guard_shape)
		printf '%s\n' "$added" | grep -qxF -- "$shape" || printf '%s\n' "$line"
	done
}

