/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
Low-level Lua interface to the Linux Kernel Crypto API for synchronous
message digest (hash) algorithms, including HMAC.
 *
This module provides a `new` function to create SHASH transform objects,
which can then be used for various hashing operations.
@see crypto_shash_tfm

@module crypto_shash
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/crypto.h>
#include <crypto/hash.h>
#include <linux/err.h>
#include <linux/slab.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

static const lunatik_class_t luacrypto_shash_tfm_class;

typedef struct {
	struct crypto_shash *tfm;
	struct shash_desc *kernel_desc; // Points to kmalloc'ed shash_desc + space
	size_t desc_alloc_len;
} luacrypto_shash_tfm_t;

LUNATIK_PRIVATECHECKER(luacrypto_check_shash_tfm, luacrypto_shash_tfm_t *);

static void luacrypto_shash_tfm_release(void *private)
{
	luacrypto_shash_tfm_t *tfm_ud = (luacrypto_shash_tfm_t *)private;
	if (!tfm_ud) {
		return;
	}
	kfree(tfm_ud->kernel_desc);
	tfm_ud->kernel_desc = NULL;
	if (tfm_ud->tfm && !IS_ERR(tfm_ud->tfm)) {
		crypto_free_shash(tfm_ud->tfm);
	}
}


/// SHASH Transform (TFM) methods.
// These methods are available on SHASH TFM objects created by `crypto_shash.new()`.
// @see crypto_shash.new
// @type crypto_shash_tfm

/***
Gets the digest size (output length) of the hash algorithm.
@function crypto_shash_tfm:digestsize
@treturn integer The digest size in bytes.
 */
static int luacrypto_shash_tfm_digestsize(lua_State *L) {
	luacrypto_shash_tfm_t *tfm_ud = luacrypto_check_shash_tfm(L, 1);
	lua_pushinteger(L, crypto_shash_digestsize(tfm_ud->tfm));
	return 1;
}
/***
Sets the key for the SHASH transform (used for HMAC).
@function crypto_shash_tfm:setkey
@tparam string key The key to use for HMAC.
@raise Error if setting the key fails.
 */
static int luacrypto_shash_tfm_setkey(lua_State *L) {
	luacrypto_shash_tfm_t *tfm_ud = luacrypto_check_shash_tfm(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	int ret = crypto_shash_setkey(tfm_ud->tfm, key, keylen);
	if (ret) return luaL_error(L, "shash_tfm:setkey: failed (%d)", ret);
	return 0;
}

/***
Computes the hash of the given data in a single operation.
For HMAC, `setkey()` must have been called first.
This function initializes, updates, and finalizes the hash calculation.
@function crypto_shash_tfm:digest
@tparam string data The data to hash.
@treturn string The computed digest (hash output).
@raise Error on failure (e.g., allocation error, crypto API error).
 */
static int luacrypto_shash_tfm_digest(lua_State *L) {
	luacrypto_shash_tfm_t *tfm_ud = luacrypto_check_shash_tfm(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int digestsize = crypto_shash_digestsize(tfm_ud->tfm);
	u8 *digest_buf = kmalloc(digestsize, gfp);
	if (!digest_buf) return luaL_error(L, "shash_tfm:digest: failed to allocate digest buffer");
	int ret = crypto_shash_digest(tfm_ud->kernel_desc, data, datalen, digest_buf);
	if (ret) {
		kfree(digest_buf);
		return luaL_error(L, "shash_tfm:digest: crypto_shash_digest failed (%d)", ret);
	}
	lua_pushlstring(
		L, (const char *)digest_buf, digestsize
	);
	kfree(digest_buf);
	return 1;
}

/***
Initializes a multi-part hash operation.
This must be called before using `update()` or `final()`.
@function crypto_shash_tfm:init
@raise Error on failure.
 */
static int luacrypto_shash_tfm_init(lua_State *L) {
	luacrypto_shash_tfm_t *tfm_ud = luacrypto_check_shash_tfm(L, 1);
	int ret = crypto_shash_init(tfm_ud->kernel_desc);
	if (ret) {
		return luaL_error(L, "shash_tfm:init: failed (%d)", ret);
	}
	return 0;
}

/***
Updates the hash state with more data.
Must be called after `init()`. Can be called multiple times.
@function crypto_shash_tfm:update
@tparam string data The data chunk to add to the hash.
@raise Error on failure.
 */
static int luacrypto_shash_tfm_update(lua_State *L) {
	luacrypto_shash_tfm_t *tfm_ud = luacrypto_check_shash_tfm(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);
	int ret = crypto_shash_update(tfm_ud->kernel_desc, data, datalen);
	if (ret) {
		return luaL_error(L, "shash_tfm:update: failed (%d)", ret);
	}
	return 0;
}

/***
Finalizes the multi-part hash operation and returns the digest.
Must be called after `init()` and any `update()` calls.
@function crypto_shash_tfm:final
@treturn string The computed digest.
@raise Error on failure.
 */
static int luacrypto_shash_tfm_final(lua_State *L) {
	luacrypto_shash_tfm_t *tfm_ud = luacrypto_check_shash_tfm(L, 1);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int digestsize = crypto_shash_digestsize(tfm_ud->tfm);
	u8 *digest_buf = kmalloc(digestsize, gfp);
	int ret;
	if (!digest_buf) return luaL_error(L, "shash_tfm:final: failed to allocate digest buffer");
	ret = crypto_shash_final(tfm_ud->kernel_desc, digest_buf);
	if (ret) {
		kfree(digest_buf);
		return luaL_error(L, "shash_tfm:final: failed (%d)", ret);
	}
	lua_pushlstring(
		L, (const char *)digest_buf, digestsize
	);
	kfree(digest_buf);
	return 1;
}

/***
Combines update and finalization for a multi-part hash operation.
Updates the hash state with the given data, then finalizes and returns the digest.
`init()` must have been called prior to calling `finup()`.
@function crypto_shash_tfm:finup
@tparam string data The final data chunk.
@treturn string The computed digest.
@raise Error on failure.
 */
static int luacrypto_shash_tfm_finup(lua_State *L) {
	luacrypto_shash_tfm_t *tfm_ud = luacrypto_check_shash_tfm(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int digestsize = crypto_shash_digestsize(tfm_ud->tfm);
	u8 *digest_buf = kmalloc(digestsize, gfp);
	int ret;
	if (!digest_buf) return luaL_error(L, "shash_tfm:finup: failed to allocate digest buffer");
	ret = crypto_shash_finup(tfm_ud->kernel_desc, data, datalen, digest_buf);
	if (ret) {
		kfree(digest_buf);
		return luaL_error(L, "shash_tfm:finup: failed (%d)", ret);
	}
	lua_pushlstring(
		L, (const char *)digest_buf, digestsize
	);
	kfree(digest_buf);
	return 1;
}

/***
Exports the internal state of the hash operation.
This allows suspending and later resuming a hash calculation via `import()`.
Must be called after `init()` and any `update()` calls if part of a multi-step operation.
@function crypto_shash_tfm:export
@treturn string The internal hash state as a binary string.
@raise Error on failure (e.g., allocation error).
 */
static int luacrypto_shash_tfm_export(lua_State *L) {
	luacrypto_shash_tfm_t *tfm_ud = luacrypto_check_shash_tfm(L, 1);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int statesize = crypto_shash_statesize(tfm_ud->tfm);
	void *state_buf = kmalloc(statesize, gfp);
	if (!state_buf) return luaL_error(L, "shash_tfm:export: failed to allocate state buffer");
	crypto_shash_export(tfm_ud->kernel_desc, state_buf);
	lua_pushlstring(
		L, (const char *)state_buf, statesize
	);
	kfree(state_buf);
	return 1;
}

/***
Imports a previously exported hash state.
This overwrites the current hash state and allows resuming a hash calculation.
The imported state must be compatible with the current hash algorithm.
@function crypto_shash_tfm:import
@tparam string state The previously exported hash state (binary string).
@raise Error on failure or if the provided state length is incorrect for the algorithm.
 */
static int luacrypto_shash_tfm_import(lua_State *L) {
	luacrypto_shash_tfm_t *tfm_ud = luacrypto_check_shash_tfm(L, 1);
	size_t statelen;
	const char *state = luaL_checklstring(L, 2, &statelen);
	unsigned int expected_statesize;
	int ret;
	expected_statesize = crypto_shash_statesize(tfm_ud->tfm);
	luaL_argcheck(
		L, statelen == expected_statesize,
		2, "incorrect state length for import"
	);
	ret = crypto_shash_import(tfm_ud->kernel_desc, state);
	if (ret) return luaL_error(L, "shash_tfm:import: failed (%d)", ret);
	return 0;
}

static const luaL_Reg luacrypto_shash_tfm_mt[] = {
	{"digestsize", luacrypto_shash_tfm_digestsize},
	{"setkey", luacrypto_shash_tfm_setkey},
	{"digest", luacrypto_shash_tfm_digest},
	{"init", luacrypto_shash_tfm_init},
	{"update", luacrypto_shash_tfm_update},
	{"final", luacrypto_shash_tfm_final},
	{"finup", luacrypto_shash_tfm_finup},
	{"export", luacrypto_shash_tfm_export},
	{"import", luacrypto_shash_tfm_import},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_shash_tfm_class = {
	.name = "crypto_shash_tfm",
	.methods = luacrypto_shash_tfm_mt,
	.release = luacrypto_shash_tfm_release,
	.sleep = true
};


/***
Creates a new SHASH transform (TFM) object.
This is the constructor function for the `crypto_shash` module.
@function crypto_shash.new
@tparam string algname The name of the hash algorithm (e.g., "sha256", "hmac(sha256)").
@treturn crypto_shash_tfm The new SHASH TFM object.
@raise Error if the TFM object or kernel descriptor cannot be allocated/initialized.
@usage local shash_mod = require("crypto_shash")
local hasher = shash_mod.new("sha256")
*/
static int luacrypto_shash_new(lua_State *L) {
	const char *algname = luaL_checkstring(L, 1);
	luacrypto_shash_tfm_t *tfm_ud;
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	size_t desc_size;
	lunatik_object_t *object = lunatik_newobject(
		L, &luacrypto_shash_tfm_class,
		sizeof(luacrypto_shash_tfm_t)
	);
	if (!object) {
		return luaL_error(L, "crypto_shash.new: failed to create underlying SHASH TFM object");
	}
	tfm_ud = (luacrypto_shash_tfm_t *)object->private;
	memset(tfm_ud, 0, sizeof(luacrypto_shash_tfm_t));

	tfm_ud->tfm = crypto_alloc_shash(algname, 0, 0);
	if (IS_ERR(tfm_ud->tfm)) {
		long err = PTR_ERR(tfm_ud->tfm);
		return luaL_error(L, "failed to allocate SHASH transform for %s (err %ld)", algname, err);
	}

	// Allocate shash_desc
	desc_size = sizeof(struct shash_desc) + crypto_shash_descsize(tfm_ud->tfm);
	tfm_ud->kernel_desc = kmalloc(desc_size, gfp);
	if (!tfm_ud->kernel_desc) {
		crypto_free_shash(tfm_ud->tfm);
		tfm_ud->tfm = NULL; // Prevent double free in release
		return luaL_error(L, "crypto_shash.new: failed to allocate descriptor memory for %s",
					algname);
	}
	tfm_ud->kernel_desc->tfm = tfm_ud->tfm;
	tfm_ud->desc_alloc_len = desc_size;
	return 1;
}


static const luaL_Reg luacrypto_shash_lib_funcs[] = {
	{"new", luacrypto_shash_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_shash, luacrypto_shash_lib_funcs, &luacrypto_shash_tfm_class, NULL);

static int __init luacrypto_shash_init(void)
{
	return 0;
}

static void __exit luacrypto_shash_exit(void)
{
}

module_init(luacrypto_shash_init);
module_exit(luacrypto_shash_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("jperon <cataclop@hotmail.com>");
MODULE_DESCRIPTION("Lunatik low-level Linux Crypto API interface (SHASH)");