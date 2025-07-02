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
* @module crypto_comp
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/crypto.h>
#include <linux/err.h>
#include <linux/slab.h>
#include <linux/limits.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>
#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_comp_check, struct crypto_comp *);

LUACRYPTO_RELEASE(comp, struct crypto_comp, crypto_free_comp, );

/***
* COMP Object methods.
* These methods are available on COMP objects created by `crypto_comp.new()`.
* @type crypto_comp
*/

/***
* Compresses the given data.
* Requires the maximum possible compressed size as an argument, as the kernel
* API needs a destination buffer of sufficient size. A common approach is to
* provide a size slightly larger than the input data (e.g., input size + a small fixed overhead or percentage).
* @function crypto_comp:compress
* @tparam string data The data to compress.
* @tparam integer max_output_len The maximum possible size of the compressed data.
* @treturn string The compressed data.
* @raise Error on failure (e.g., allocation error, crypto API error).
*/
static int luacrypto_comp_compress(lua_State *L) {
	struct crypto_comp *tfm = luacrypto_comp_check(L, 1);
	size_t datalen_sz;
	const char *data = luaL_checklstring(L, 2, &datalen_sz);
	lua_Integer max_output_len_l = luaL_checkinteger(L, 3);

	luaL_argcheck(L, max_output_len_l >= 0, 3, "maximum output length must be non-negative");

	if (datalen_sz > UINT_MAX)
		luaL_error(L, "input data too large (exceeds UINT_MAX)");
	unsigned int datalen_uint = (unsigned int)datalen_sz;

	if (max_output_len_l > UINT_MAX)
		luaL_error(L, "maximum output length exceeds UINT_MAX");
	unsigned int max_output_len_uint = (unsigned int)max_output_len_l;

	if (max_output_len_uint == 0) {
		luaL_argcheck(L, datalen_uint == 0, 2, "cannot compress non-empty data into a 0-byte buffer");
		lua_pushlstring(L, "", 0);
		return 1;
	}

	luaL_Buffer b;
	u8 *output_buf = luaL_buffinitsize(L, &b, max_output_len_uint);

	lunatik_try(L, crypto_comp_compress, tfm, (const u8 *)data, datalen_uint, output_buf, &max_output_len_uint);

	luaL_pushresultsize(&b, max_output_len_uint);
	return 1;
}

/***
* Decompresses the given data.
* Requires the maximum possible decompressed size as an argument, as the kernel
* API needs a destination buffer of sufficient size.
* @function crypto_comp:decompress
* @tparam string data The data to decompress.
* @tparam integer max_decompressed_len The maximum possible size of the decompressed data.
* @treturn string The decompressed data.
* @raise Error on failure (e.g., allocation error, crypto API error, input data corrupted,
*        `max_decompressed_len` too small).
*/
static int luacrypto_comp_decompress(lua_State *L) {
	struct crypto_comp *tfm = luacrypto_comp_check(L, 1);
	size_t datalen_sz;
	const char *data = luaL_checklstring(L, 2, &datalen_sz);
	lua_Integer max_decompressed_len_l = luaL_checkinteger(L, 3);

	if (datalen_sz > UINT_MAX)
		luaL_error(L, "input data too large (exceeds UINT_MAX)");
	unsigned int datalen_uint = (unsigned int)datalen_sz;

	luaL_argcheck(L, max_decompressed_len_l >= 0, 3, "maximum decompressed length must be non-negative");
	luaL_argcheck(L, max_decompressed_len_l <= UINT_MAX, 3, "maximum decompressed length exceeds UINT_MAX");
	unsigned int max_output_len_uint = (unsigned int)max_decompressed_len_l;

	if (datalen_uint == 0) {
		lua_pushlstring(L, "", 0);
		return 1;
	}

	if (max_output_len_uint == 0)
		luaL_error(L, "cannot decompress non-empty data into a 0-byte buffer");

	luaL_Buffer b;
	u8 *output_buf = luaL_buffinitsize(L, &b, max_output_len_uint);

	lunatik_try(L, crypto_comp_decompress, tfm, (const u8 *)data, datalen_uint, output_buf, &max_output_len_uint);

	luaL_pushresultsize(&b, max_output_len_uint);
	return 1;
}

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
* @function crypto_comp.new
* @tparam string algname The name of the compression algorithm (e.g., "lz4", "deflate").
* @treturn crypto_comp The new COMP TFM object.
* @raise Error if the TFM object cannot be allocated/initialized.
* @usage
*   local comp = require("crypto_comp")
*   local compressor = comp.new("lz4")
 */
LUACRYPTO_NEW(comp, struct crypto_comp, crypto_alloc_comp, luacrypto_comp_class, tfm, );

static const luaL_Reg luacrypto_comp_lib[] = {
	{"new", luacrypto_comp_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_comp, luacrypto_comp_lib, &luacrypto_comp_class, NULL);

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

