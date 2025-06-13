#!/bin/sh
# SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

cat "$@" | sed "s/.*luaconf.h.*//g" | cpp -Ilua/ -D_KERNEL -E -pipe | \
	grep API | sed "s/.*(\(\w*\))\s*(.*/EXPORT_SYMBOL(\1);/g"

