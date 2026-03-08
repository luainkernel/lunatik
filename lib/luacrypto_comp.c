/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to synchronous compression algorithms.
* @module crypto.comp
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/crypto.h>
#include <linux/err.h>
#include <linux/slab.h>
#include <linux/limits.h>

#include "luacrypto.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0))
#warning "crypto_comp API was removed in Linux 6.15, skip COMP module"
#else
LUNATIK_PRIVATECHECKER(luacrypto_comp_check, struct crypto_comp *);

LUACRYPTO_RELEASER(comp, struct crypto_comp, crypto_free_comp);

#define LUACRYPTO_COMP_OPERATION(name)									\
static int luacrypto_comp_##name(lua_State *L)								\
{													\
	struct crypto_comp *tfm = luacrypto_comp_check(L, 1);						\
	size_t datalen;											\
	const u8 *data = (const u8 *)luaL_checklstring(L, 2, &datalen);				\
	lunatik_checkbounds(L, 2, datalen, 1, UINT_MAX);						\
	unsigned int max_len = (unsigned int)lunatik_checkinteger(L, 3, 1, UINT_MAX);	\
													\
	luaL_Buffer B;											\
	u8 *output_buf = luaL_buffinitsize(L, &B, max_len);						\
													\
	lunatik_try(L, crypto_comp_##name, tfm, data, (unsigned int)datalen, output_buf, &max_len);	\
	luaL_pushresultsize(&B, max_len);								\
	return 1;											\
}

/***
* Compresses data.
* @function compress
* @tparam string data input data
* @tparam integer max_len maximum size of compressed output
* @treturn string compressed data
* @raise on compression failure
*/
LUACRYPTO_COMP_OPERATION(compress);

/***
* Decompresses data.
* @function decompress
* @tparam string data compressed input
* @tparam integer max_len maximum size of decompressed output
* @treturn string decompressed data
* @raise on decompression failure
*/
LUACRYPTO_COMP_OPERATION(decompress);

static const luaL_Reg luacrypto_comp_mt[] = {
	{"compress", luacrypto_comp_compress},
	{"decompress", luacrypto_comp_decompress},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_comp_class = {
	.name = "crypto_comp",
	.methods = luacrypto_comp_mt,
	.release = luacrypto_comp_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

/***
* Creates a new COMP transform object.
* @function new
* @tparam string algname algorithm name (e.g., "lz4", "deflate")
* @treturn crypto_comp
* @raise on allocation failure
* @usage
*   local comp = require("crypto").comp
*   local c = comp("lz4")
*/
LUACRYPTO_NEW(comp, struct crypto_comp, crypto_alloc_comp, luacrypto_comp_class);

static const luaL_Reg luacrypto_comp_lib[] = {
	{"new", luacrypto_comp_new},
	{NULL, NULL}
};

LUNATIK_CLASSES(crypto_comp, &luacrypto_comp_class);
LUNATIK_NEWLIB(crypto_comp, luacrypto_comp_lib, luacrypto_comp_classes, NULL);
#endif

static int __init luacrypto_comp_init(void)
{
	return 0;
}

static void __exit luacrypto_comp_exit(void)
{
}

module_init(luacrypto_comp_init);
module_exit(luacrypto_comp_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("jperon <cataclop@hotmail.com>");
MODULE_DESCRIPTION("Lunatik low-level Linux Crypto API interface (COMP)");

