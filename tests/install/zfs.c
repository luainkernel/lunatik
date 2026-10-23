/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Stand-in for OpenZFS's zfs.ko, which run.sh builds for depmod to read and never loads: ZFS's own
* Lua exports lua_createtable, a name every Lunatik binding imports.
*/

#include <linux/module.h>

int lua_createtable;
EXPORT_SYMBOL(lua_createtable);

MODULE_LICENSE("Dual MIT/GPL");

