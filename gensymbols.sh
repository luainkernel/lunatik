#!/bin/sh
# SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

sed "s/.*luaconf.h.*//g" "$@" | \
        ${CC} -Ilua/ -D_KERNEL -DLUNATIK_GENSYMBOLS -E - | \
	grep API | sed "s/.*(\(\w*\))\s*(.*/EXPORT_SYMBOL(\1);/g"

