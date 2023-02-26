#!/bin/sh
cat "$@" | sed "s/.*luaconf.h.*//g" | cpp -Ilua/ -D_KERNEL -E -pipe | \
	grep API | sed "s/.*(\(\w*\))\s*(.*/EXPORT_SYMBOL(\1);/g"

