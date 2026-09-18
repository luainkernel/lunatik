#!/usr/bin/env bash
# Names a field a change adds to lunatik_runtime_t, the block Lua keeps in every state's
# extra space: lua_newthread copies it into each coroutine, so a field there is either fixed
# at creation or read only through the main state, as ready is. #851 put a flag set around a
# callback there, and a coroutine made before the callback would have read it clear while one
# made inside would have kept it set. A fact a coroutine may read while it changes lives on
# the runtime object when the core sets it, in the registry when a binding does. Takes file
# paths; silent on files that are not
# lunatik_conf.h or add no line to the struct. CHECK_BASE names the revision to diff against
# on a committed branch; HEAD otherwise.

for file in "$@"; do
	[ "$(basename "$file")" = lunatik_conf.h ] || continue
	added=$(git -C "$(dirname "$file")" diff "${CHECK_BASE:-HEAD}" -U0 -- "$(basename "$file")" 2>/dev/null |
		awk '/^@@/ { hunk = $0 } /^\+[[:space:]]/ && hunk ~ /lunatik_runtime_s|lunatik_runtime_t/ { print }')
	[ -z "$added" ] && continue
	echo "$file adds to lunatik_runtime_t, which lua_newthread copies into every coroutine:"
	echo "$added"
	echo "A field there is fixed at creation or read only through the main state, as ready is; a fact a coroutine may read while it changes lives on the runtime object, beside owner."
done

