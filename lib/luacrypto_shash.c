/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Crypto API for synchronous
* message digest (hash) algorithms, including HMAC.
*
* This module provides a `new` function to create SHASH transform objects,
* which can then be used for various hashing operations.
*
* @module crypto.shash
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>
#include <crypto/hash.h>
#include <linux/err.h>
#include <linux/slab.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_shash_check, struct shash_desc *);

static inline void luacrypto_shash_release_tfm(struct shash_desc *obj)
{
	if (obj->tfm)
		crypto_free_shash(obj->tfm);
}

LUACRYPTO_RELEASER(shash, struct shash_desc, lunatik_free, luacrypto_shash_release_tfm);

/***
* SHASH object methods.
* These methods are available on SHASH objects created by `crypto_shash.new()`.
* @see new
* @type SHASH
*/

/***
* Gets the digest size (output length) of the hash algorithm.
* @function digestsize
* @treturn integer The digest size in bytes.
*/
static int luacrypto_shash_digestsize(lua_State *L) {
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	lua_pushinteger(L, crypto_shash_digestsize(sdesc->tfm));
	return 1;
}

/***
* Sets the key for the SHASH transform (used for HMAC).
* @function setkey
* @tparam string key The key to use for HMAC.
* @raise Error if setting the key fails.
*/
static int luacrypto_shash_setkey(lua_State *L) {
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_try(L, crypto_shash_setkey, sdesc->tfm, key, keylen);
	return 0;
}

/***
* Computes the hash of the given data in a single operation.
* For HMAC, `setkey()` must have been called first.
* This function initializes, updates, and finalizes the hash calculation.
* @function digest
* @tparam string data The data to hash.
* @treturn string The computed digest (hash output).
* @raise Error on failure (e.g., allocation error, crypto API error).
*/
static int luacrypto_shash_digest(lua_State *L) {
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);
	unsigned int digestsize = crypto_shash_digestsize(sdesc->tfm);
	luaL_Buffer b;
	u8 *digest_buf = luaL_buffinitsize(L, &b, digestsize);

	lunatik_try(L, crypto_shash_digest, sdesc, data, datalen, digest_buf);
	luaL_pushresultsize(&b, digestsize);
	return 1;
}

/***
* Initializes a multi-part hash operation.
* This must be called before using `update()` or `final()`.
* @function init
* @raise Error on failure.
*/
static int luacrypto_shash_init_method(lua_State *L) {
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);

	lunatik_try(L, crypto_shash_init, sdesc);
	return 0;
}

/***
* Updates the hash state with more data.
* Must be called after `init()`. Can be called multiple times.
* @function update
* @tparam string data The data chunk to add to the hash.
* @raise Error on failure.
*/
static int luacrypto_shash_update(lua_State *L) {
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);

	lunatik_try(L, crypto_shash_update, sdesc, data, datalen);
	return 0;
}

/***
* Finalizes the multi-part hash operation and returns the digest.
* Must be called after `init()` and any `update()` calls.
* @function final
* @treturn string The computed digest.
* @raise Error on failure.
*/
static int luacrypto_shash_final(lua_State *L) {
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	unsigned int digestsize = crypto_shash_digestsize(sdesc->tfm);
	luaL_Buffer b;
	u8 *digest_buf = luaL_buffinitsize(L, &b, digestsize);

	lunatik_try(L, crypto_shash_final, sdesc, digest_buf);
	luaL_pushresultsize(&b, digestsize);
	return 1;
}

/***
* Combines update and finalization for a multi-part hash operation.
* Updates the hash state with the given data, then finalizes and returns the digest.
* `init()` must have been called prior to calling `finup()`.
* @function finup
* @tparam string data The final data chunk.
* @treturn string The computed digest.
* @raise Error on failure.
*/
static int luacrypto_shash_finup(lua_State *L) {
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);
	unsigned int digestsize = crypto_shash_digestsize(sdesc->tfm);
	luaL_Buffer b;
	u8 *digest_buf = luaL_buffinitsize(L, &b, digestsize);

	lunatik_try(L, crypto_shash_finup, sdesc, data, datalen, digest_buf);
	luaL_pushresultsize(&b, digestsize);
	return 1;
}

/***
* Exports the internal state of the hash operation.
* This allows suspending and later resuming a hash calculation via `import()`.
* Must be called after `init()` and any `update()` calls if part of a multi-step operation.
* @function export
* @treturn string The internal hash state as a binary string.
* @raise Error on failure (e.g., allocation error).
*/
static int luacrypto_shash_export(lua_State *L) {
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	unsigned int statesize = crypto_shash_statesize(sdesc->tfm);
	luaL_Buffer b;
	void *state_buf = luaL_buffinitsize(L, &b, statesize);
	crypto_shash_export(sdesc, state_buf);
	luaL_pushresultsize(&b, statesize);
	return 1;
}

/***
* Imports a previously exported hash state.
* This overwrites the current hash state and allows resuming a hash calculation.
* The imported state must be compatible with the current hash algorithm.
* @function import
* @tparam string state The previously exported hash state (binary string).
* @raise Error on failure or if the provided state length is incorrect for the algorithm.
*/
static int luacrypto_shash_import(lua_State *L) {
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t statelen;
	const char *state = luaL_checklstring(L, 2, &statelen);
	unsigned int expected_statesize = crypto_shash_statesize(sdesc->tfm);
	luaL_argcheck(L, statelen == expected_statesize, 2, "incorrect state length for import");
	lunatik_try(L, crypto_shash_import, sdesc, state);
	return 0;
}

static const luaL_Reg luacrypto_shash_mt[] = {
	{"digestsize", luacrypto_shash_digestsize},
	{"setkey", luacrypto_shash_setkey},
	{"digest", luacrypto_shash_digest},
	{"init", luacrypto_shash_init_method},
	{"update", luacrypto_shash_update},
	{"final", luacrypto_shash_final},
	{"finup", luacrypto_shash_finup},
	{"export", luacrypto_shash_export},
	{"import", luacrypto_shash_import},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

/***
* Lunatik class definition for SHASH objects.
* This structure binds the C implementation (luacrypto_shash_tfm_t, methods, release function)
* to the Lua object system managed by Lunatik.
*/
static const lunatik_class_t luacrypto_shash_class = {
	.name = "crypto_shash",
	.methods = luacrypto_shash_mt,
	.release = luacrypto_shash_release,
	.flags = LUNATIK_CLASS_SLEEPABLE,
	.pointer = true,
};

/***
* Creates a new SHASH object.
* This is the constructor function for the `crypto_shash` module.
* @function new
* @tparam string algname The name of the hash algorithm (e.g., "sha256", "hmac(sha256)").
* @treturn crypto_shash The new SHASH object.
* @raise Error if the TFM object or kernel descriptor cannot be allocated/initialized.
* @usage
*   local shash_mod = require("crypto.shash")
*   local hasher = shash_mod.new("sha256")
* @within shash
*/
static struct shash_desc *luacrypto_shash_new_sdesc(lua_State *L, struct crypto_shash *tfm)
{
	size_t desc_size = sizeof(struct shash_desc) + crypto_shash_descsize(tfm);
	struct shash_desc *sdesc = lunatik_checkalloc(L, desc_size);
	sdesc->tfm = tfm;
	return sdesc;
}

LUACRYPTO_NEW(shash, struct crypto_shash, crypto_alloc_shash, luacrypto_shash_class, luacrypto_shash_new_sdesc);

static const luaL_Reg luacrypto_shash_lib[] = {
	{"new", luacrypto_shash_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_shash, luacrypto_shash_lib, &luacrypto_shash_class, NULL);

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

