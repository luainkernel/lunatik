/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Stand-in for OpenZFS's zfs.ko, which zfs.sh loads beside lunatik.ko: ZFS's own Lua exports
* lua_createtable, a name Lua's C API declares.
*/

#include <linux/module.h>

int lua_createtable;
EXPORT_SYMBOL(lua_createtable);

MODULE_LICENSE("Dual MIT/GPL");

