#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A byte written for one reader stays written after that reader goes. #1179's
# walk stopped reading the entry's key as a C string, strscpy into a buffer,
# and the entry kept the NUL it stored after the key and the byte it allocated
# for it, with nothing left in the file that stops at a NUL; two review passes
# read the store as part of the entry and not as a value with a reader.
#
# This one reads a C file for a store that terminates an array, x[n] = '\0',
# and names it when no call in the file that reads a C string, strlen, strcmp,
# strscpy, a format with %s, lua_pushstring and their kin, takes that array.
# The reader may sit in another file, behind a pointer the array is handed to,
# so it annotates: the reviewer answers with the reader or with the fixup that
# drops the byte.
#
# Usage: bash tools/checks/terminator.sh <file>...

readers='\b(strlen|strnlen|strcmp|strncmp|strcasecmp|strncasecmp|strscpy|strlcpy|strcpy|strncpy|kstrdup|kstrndup|strchr|strrchr|strstr|strsep|strspn|strpbrk|sscanf|kstrto[a-z0-9_]+|simple_strto[a-z]+|match_string|sysfs_streq|lua_pushstring|lua_pushfstring|luaL_checkstring|luaL_optstring|kasprintf|kvasprintf|snprintf|scnprintf|sprintf|printk|pr_[a-z_]+|seq_printf|seq_puts|dev_[a-z]+\(|kallsyms_lookup_name|register_kprobe)\b|%s'

status=0

for f in "$@"; do
	case "$f" in *.c|*.h) ;; *) continue ;; esac
	[ -f "$f" ] || continue
	while IFS=: read -r line text; do
		name=$(sed -E "s/^.*[^A-Za-z0-9_]([A-Za-z_][A-Za-z0-9_]*)\[[^]]*\] *= *'\\\\0' *;.*$/\1/" <<< "$text")
		[ "$name" != "$text" ] || continue
		grep -E "$readers" "$f" | grep -qE "(^|[^A-Za-z0-9_])$name([^A-Za-z0-9_]|$)" && continue
		printf '%s:%s: %s is NUL-terminated here and nothing in the file reads it as a C string\n' "$f" "$line" "$name"
		status=1
	done < <(grep -nE "\[[^]]*\] *= *'\\\\0' *;" "$f")
done

[ $status -eq 0 ] || echo "a terminator is written for a reader that stops at it: name the reader, or drop the byte with the +1 that allocates it"
exit $status

