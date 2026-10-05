#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a change that sizes Lua's extra space again, which holds the runtime's pointer alone:
# lua_newthread copies it into each coroutine when it is made and lua_close frees it with the
# state, so a fact kept there is right only while fixed and only while the state lives. #851 put
# a flag set around a callback there, and a coroutine made before the callback would have read it
# clear while one made inside would have kept it set. A fact the core keeps about a runtime lives
# in lunatik_runtime_t, which a reference reaches; one a binding sets and reads lives in the
# registry. Takes file paths; silent on files that are not lunatik_conf.h or add no line naming
# LUA_EXTRASPACE. CHECK_BASE names the revision to diff against on a committed branch; HEAD
# otherwise.

for file in "$@"; do
	[ "$(basename "$file")" = lunatik_conf.h ] || continue
	added=$(git -C "$(dirname "$file")" diff "${CHECK_BASE:-HEAD}" -U0 -- "$(basename "$file")" 2>/dev/null |
		grep -E '^\+.*\bLUA_EXTRASPACE\b')
	[ -z "$added" ] && continue
	echo "$file sizes Lua's extra space, which lua_newthread copies into every coroutine:"
	echo "$added"
	echo "The extra space holds the runtime's pointer alone; a fact about a runtime lives in lunatik_runtime_t, one a binding sets and reads in the registry."
done

