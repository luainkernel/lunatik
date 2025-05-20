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

static const lunatik_class_t luacrypto_comp_tfm_class;

typedef struct {
	struct crypto_comp *tfm;
} luacrypto_comp_tfm_t;

LUNATIK_PRIVATECHECKER(luacrypto_check_comp_tfm, luacrypto_comp_tfm_t *);

static void luacrypto_comp_tfm_release(void *private)
{
	luacrypto_comp_tfm_t *tfm_ud = (luacrypto_comp_tfm_t *)private;
	if (tfm_ud && tfm_ud->tfm && !IS_ERR(tfm_ud->tfm)) {
		crypto_free_comp(tfm_ud->tfm);
	}
}


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
static int luacrypto_comp_tfm_compress(lua_State *L) {
	luacrypto_comp_tfm_t *tfm_ud = luacrypto_check_comp_tfm(L, 1);
	size_t datalen_sz;
	const char *data = luaL_checklstring(L, 2, &datalen_sz);
	lua_Integer max_output_len_l = luaL_checkinteger(L, 3);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int datalen_uint;
	unsigned int max_output_len_uint;
	unsigned int actual_output_len_uint;
	u8 *output_buf;
	int ret;

	luaL_argcheck(L, max_output_len_l >= 0, 3, "maximum output length must be non-negative");

	if (datalen_sz > UINT_MAX) {
		return luaL_error(L, "comp_tfm:compress: input data too large (exceeds UINT_MAX)");
	}
	datalen_uint = (unsigned int)datalen_sz;

	if (max_output_len_l > UINT_MAX) {
		return luaL_error(L, "comp_tfm:compress: maximum output length exceeds UINT_MAX");
	}
	max_output_len_uint = (unsigned int)max_output_len_l;

	if (max_output_len_uint == 0) {
		luaL_argcheck(L, datalen_uint == 0, 2, "cannot compress non-empty data into a 0-byte buffer");
		lua_pushlstring(L, "", 0);
		return 1;
	}

	output_buf = kmalloc(max_output_len_uint, gfp);
	if (!output_buf) {
		return luaL_error(L, "comp_tfm:compress: failed to allocate output buffer");
	}

	actual_output_len_uint = max_output_len_uint; /* dlen is in/out */ /* The kernel updates this with the actual compressed size */
	ret = crypto_comp_compress(tfm_ud->tfm, (const u8 *)data, datalen_uint,
				   output_buf, &actual_output_len_uint);

	if (ret) {
		kfree(output_buf);
		return luaL_error(L, "comp_tfm:compress: crypto_comp_compress failed (%d)", ret);
	}

	lua_pushlstring(L, (const char *)output_buf, actual_output_len_uint);
	kfree(output_buf);
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
static int luacrypto_comp_tfm_decompress(lua_State *L) {
	luacrypto_comp_tfm_t *tfm_ud = luacrypto_check_comp_tfm(L, 1);
	size_t datalen_sz;
	const char *data = luaL_checklstring(L, 2, &datalen_sz);
	lua_Integer max_decompressed_len_l = luaL_checkinteger(L, 3);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int datalen_uint;
	unsigned int max_output_len_uint;
	unsigned int actual_output_len_uint;
	u8 *output_buf;
	int ret;

	if (datalen_sz > UINT_MAX) {
		return luaL_error(L, "comp_tfm:decompress: input data too large (exceeds UINT_MAX)");
	}
	datalen_uint = (unsigned int)datalen_sz;

	luaL_argcheck(L, max_decompressed_len_l >= 0, 3, "maximum decompressed length must be non-negative");
	luaL_argcheck(L, max_decompressed_len_l <= UINT_MAX, 3, "maximum decompressed length exceeds UINT_MAX");
	max_output_len_uint = (unsigned int)max_decompressed_len_l;

	if (datalen_uint == 0) {
		lua_pushlstring(L, "", 0);
		return 1;
	}


	if (max_output_len_uint == 0) {
		/*
		* If input is non-empty (we are here because datalen_uint > 0) and max_output_len_uint is 0,
		* this is an error: cannot decompress non-empty data into a 0-byte buffer.
		*/
		return luaL_error(L, "comp_tfm:decompress: cannot decompress non-empty data into a 0-byte buffer");
	}

	output_buf = kmalloc(max_output_len_uint, gfp);
	if (!output_buf) {
		/* -ENOMEM */
		return luaL_error(L, "comp_tfm:decompress: failed to allocate output buffer");
	}

	actual_output_len_uint = max_output_len_uint; /* dlen is in/out */
	ret = crypto_comp_decompress(tfm_ud->tfm, (const u8 *)data, datalen_uint,
				     output_buf, &actual_output_len_uint);

	if (ret) {
		kfree(output_buf);
		/* -EINVAL often means output buffer too small */
		return luaL_error(L, "comp_tfm:decompress: crypto_comp_decompress failed (%d, possibly buffer too small or data corrupted)", ret); /* -EINVAL, -EBADMSG, etc. */
	}
	lua_pushlstring(L, (const char *)output_buf, actual_output_len_uint);
	kfree(output_buf);
	return 1;
}

static const luaL_Reg luacrypto_comp_tfm_mt[] = {
	{"compress", luacrypto_comp_tfm_compress},
	{"decompress", luacrypto_comp_tfm_decompress},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_comp_tfm_class = {
	.name = "crypto_comp_tfm",
	.methods = luacrypto_comp_tfm_mt,
	.release = luacrypto_comp_tfm_release,
	.sleep = true,
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
static int luacrypto_comp_new(lua_State *L) {
	const char *algname = luaL_checkstring(L, 1);
	luacrypto_comp_tfm_t *tfm_ud;
	lunatik_object_t *object = lunatik_newobject(
		L, &luacrypto_comp_tfm_class,
		sizeof(luacrypto_comp_tfm_t)
	);
	if (!object) {
		return luaL_error(L, "crypto_comp.new: failed to create underlying COMP TFM object");
	}
	tfm_ud = (luacrypto_comp_tfm_t *)object->private;
	memset(tfm_ud, 0, sizeof(luacrypto_comp_tfm_t));

	tfm_ud->tfm = crypto_alloc_comp(algname, 0, 0);
	if (IS_ERR(tfm_ud->tfm)) {
		long err = PTR_ERR(tfm_ud->tfm);
		tfm_ud->tfm = NULL;
		return luaL_error(L, "failed to allocate COMP transform for %s (err %ld)", algname, err);
	}

	return 1;
}

static const luaL_Reg luacrypto_comp_lib_funcs[] = {
	{"new", luacrypto_comp_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_comp, luacrypto_comp_lib_funcs, &luacrypto_comp_tfm_class, NULL);

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
