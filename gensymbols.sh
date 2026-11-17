#!/bin/sh
#
# SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#

format="EXPORT_SYMBOL(\1);"
# -p: the kernel loads no two modules that export one name, and zfs.ko exports Lua's API under Lua's names
[ "$1" = "-p" ] && { format="#define \1 lunatik_\1"; shift; }

sed "s/.*luaconf.h.*//g" "$@" | \
        ${CC} -Ilua/ -D_KERNEL -E - | \
	grep API | sed "s/.*(\(\w*\))\s*(.*/$format/g"

