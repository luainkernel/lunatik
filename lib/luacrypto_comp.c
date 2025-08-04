/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Crypto API for synchronous
* compression algorithms.
*
* This module provides a `new` function to create COMP transform objects,
* which can then be used for compression and decompression.
*
* @module crypto.comp
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/crypto.h>
#include <linux/err.h>
#include <linux/slab.h>
#include <linux/limits.h>
#include <linux/version.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

#include "luacrypto.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0))
#warning "crypto_comp API was removed in Linux 6.15, skip COMP module"
#else
LUNATIK_PRIVATECHECKER(luacrypto_comp_check, struct crypto_comp *);

LUACRYPTO_RELEASER(comp, struct crypto_comp, crypto_free_comp, NULL);

/***
* COMP Object methods.
* These methods are available on COMP objects created by `comp.new()`.
* @see new
* @type COMP
*/

#define LUACRYPTO_COMP_OPERATION(name)									\
static int luacrypto_comp_##name(lua_State *L) {							\
	struct crypto_comp *tfm = luacrypto_comp_check(L, 1);						\
	size_t datalen;											\
	const u8 *data = (const u8 *)luaL_checklstring(L, 2, &datalen);					\
	lunatik_checkbounds(L, 2, datalen, 1, UINT_MAX);						\
	unsigned int max_len = lunatik_checkuint(L, 3);							\
													\
	luaL_Buffer b;											\
	u8 *output_buf = luaL_buffinitsize(L, &b, max_len);						\
													\
	lunatik_try(L, crypto_comp_##name, tfm, data, (unsigned int)datalen, output_buf, &max_len);	\
	luaL_pushresultsize(&b, max_len);								\
	return 1;											\
}

/***
* Compresses the given data.
* Requires the maximum possible compressed size as an argument, as the kernel
* API needs a destination buffer of sufficient size. A common approach is to
* provide a size slightly larger than the input data (e.g., input size + a small fixed overhead or percentage).
* @function compress
* @tparam string data The data to compress.
* @tparam integer max_output_len The maximum possible size of the compressed data.
* @treturn string The compressed data.
* @raise Error on failure (e.g., allocation error, crypto API error).
*/
LUACRYPTO_COMP_OPERATION(compress);

/***
* Decompresses the given data.
* Requires the maximum possible decompressed size as an argument, as the kernel
* API needs a destination buffer of sufficient size.
* @function decompress
* @tparam string data The data to decompress.
* @tparam integer max_output_len The maximum possible size of the decompressed data.
* @treturn string The decompressed data.
* @raise Error on failure (e.g., allocation error, crypto API error, input data corrupted,
*        `max_output_len` too small).
*/
LUACRYPTO_COMP_OPERATION(decompress);

static const luaL_Reg luacrypto_comp_mt[] = {
	{"compress", luacrypto_comp_compress},
	{"decompress", luacrypto_comp_decompress},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_comp_class = {
	.name = "crypto_comp",
	.methods = luacrypto_comp_mt,
	.release = luacrypto_comp_release,
	.sleep = true,
	.pointer = true,
};

/***
* Creates a new COMP transform (TFM) object.
* This is the constructor function for the `crypto_comp` module.
* @function new
* @tparam string algname The name of the compression algorithm (e.g., "lz4", "deflate").
* @treturn comp The new COMP TFM object.
* @raise Error if the TFM object cannot be allocated/initialized.
* @usage
*   local comp = require("crypto.comp")
*   local compressor = comp.new("lz4")
* @within comp
*/
LUACRYPTO_NEW(comp, struct crypto_comp, crypto_alloc_comp, luacrypto_comp_class, NULL);

static const luaL_Reg luacrypto_comp_lib[] = {
	{"new", luacrypto_comp_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_comp, luacrypto_comp_lib, &luacrypto_comp_class, NULL);
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

