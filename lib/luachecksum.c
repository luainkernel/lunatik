/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/kernel.h>
#include <linux/module.h>
#include <asm-generic/checksum.h>

#include <lua.h>
#include <lualib.h>
#include <lunatik.h>

typedef struct luachecksum_s {
	int unused;
} luachecksum_t;

LUNATIK_PRIVATECHECKER(luachecksum_check, luachecksum_t *);

static int luachecksum_csumpartial(lua_State *L) {
	void *data = lua_touserdata(L, 1);
	int len = luaL_checkinteger(L, 2);

	if (data) {
		__wsum sum = csum_partial(data, len, 0);
		lua_pushinteger(L, csum_fold(sum));
	}
	return 1;
}

static const luaL_Reg luachecksum_lib[] = {
	{"csum", luachecksum_csumpartial},
	{NULL, NULL}
};

LUNATIK_NEWLIB(checksum, luachecksum_lib, NULL, NULL);

static int __init luachecksum_init(void)
{
	return 0;
}

static void __exit luachecksum_exit(void)
{
}

module_init(luachecksum_init);
module_exit(luachecksum_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Carlos Carvalho <carloslack@gmail.com>");
MODULE_DESCRIPTION("Lunatik interface to checksum abstractions.");

