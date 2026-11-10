#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names, after a build, an object of the tree's own C that defines no symbol, and exits 1 when there is
# one: a unit wholly under a guard the kernel it built against leaves unset compiles to nothing, and the
# build passes without it. #2360's lib/luacrypto_kpp.c sits under IS_REACHABLE(CONFIG_CRYPTO_ECDH), which
# no defconfig the CI builds sets, and the job compiled crypto.kpp on no kernel until #2360 set it.
#
# Usage: bash tools/checks/empty-units.sh [tree], after make in that tree

tree=${1:-.}
empty=$(for source in "$tree"/lunatik*.c "$tree"/lib/*.c; do
	object=${source%.c}.o
	[ -f "$object" ] && [ -z "$(nm --defined-only "$object")" ] && echo "${object#"$tree"/}"
done)
[ -n "$empty" ] || exit 0
echo "empty-units: these compiled to nothing, so the kernel built against sets no option their guard asks for; the job's options set it:"
printf '%s\n' "$empty" | sed 's/^/  /'
exit 1

