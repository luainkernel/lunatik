/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to synchronous message digest (hash) algorithms, including HMAC.
* @module crypto.shash
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/hash.h>
#include <linux/err.h>
#include <linux/slab.h>

#include <lunatik.h>

#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_shash_check, struct shash_desc *);

static void luacrypto_shash_release(void *private)
{
	struct shash_desc *obj = (struct shash_desc *)private;
	if (obj) {
		if (obj->tfm)
			crypto_free_shash(obj->tfm);
		lunatik_free(obj);
	}
}

/***
* Returns the digest size in bytes.
* @function digestsize
* @treturn integer
*/
static int luacrypto_shash_digestsize(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	lua_pushinteger(L, crypto_shash_digestsize(sdesc->tfm));
	return 1;
}

/***
* Sets the key (required for HMAC algorithms).
* @function setkey
* @tparam string key
* @raise on invalid key or algorithm error
*/
static int luacrypto_shash_setkey(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_try(L, crypto_shash_setkey, sdesc->tfm, key, keylen);
	return 0;
}

/***
* Computes the digest of data in a single call.
* @function digest
* @tparam string data
* @treturn string digest bytes
* @raise on hash failure
*/
static int luacrypto_shash_digest(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);
	unsigned int digestsize = crypto_shash_digestsize(sdesc->tfm);
	luaL_Buffer B;
	u8 *digest_buf = luaL_buffinitsize(L, &B, digestsize);

	lunatik_try(L, crypto_shash_digest, sdesc, data, datalen, digest_buf);
	luaL_pushresultsize(&B, digestsize);
	return 1;
}

/***
* Initializes the hash state for incremental hashing.
* @function init
* @raise on initialization failure
*/
static int luacrypto_shash_init_method(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);

	lunatik_try(L, crypto_shash_init, sdesc);
	return 0;
}

/***
* Feeds data into the running hash.
* @function update
* @tparam string data
* @raise on hash failure
*/
static int luacrypto_shash_update(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);

	lunatik_try(L, crypto_shash_update, sdesc, data, datalen);
	return 0;
}

/***
* Finalizes and returns the digest.
* @function final
* @treturn string digest bytes
* @raise on hash failure
*/
static int luacrypto_shash_final(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	unsigned int digestsize = crypto_shash_digestsize(sdesc->tfm);
	luaL_Buffer B;
	u8 *digest_buf = luaL_buffinitsize(L, &B, digestsize);

	lunatik_try(L, crypto_shash_final, sdesc, digest_buf);
	luaL_pushresultsize(&B, digestsize);
	return 1;
}

/***
* Feeds final data and returns the digest (update + final in one call).
* @function finup
* @tparam string data
* @treturn string digest bytes
* @raise on hash failure
*/
static int luacrypto_shash_finup(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);
	unsigned int digestsize = crypto_shash_digestsize(sdesc->tfm);
	luaL_Buffer B;
	u8 *digest_buf = luaL_buffinitsize(L, &B, digestsize);

	lunatik_try(L, crypto_shash_finup, sdesc, data, datalen, digest_buf);
	luaL_pushresultsize(&B, digestsize);
	return 1;
}

/***
* Exports the current internal hash state.
* @function export
* @treturn string opaque state blob
*/
static int luacrypto_shash_export(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	unsigned int statesize = crypto_shash_statesize(sdesc->tfm);
	luaL_Buffer B;
	void *state_buf = luaL_buffinitsize(L, &B, statesize);
	crypto_shash_export(sdesc, state_buf);
	luaL_pushresultsize(&B, statesize);
	return 1;
}

/***
* Restores a previously exported hash state.
* @function import
* @tparam string state blob returned by `export()`
* @raise on length mismatch
*/
static int luacrypto_shash_import(lua_State *L)
{
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
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_shash_class = {
	.name = "crypto_shash",
	.methods = luacrypto_shash_mt,
	.release = luacrypto_shash_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

/***
* Creates a new SHASH object.
* @function new
* @tparam string algname algorithm name (e.g., "sha256", "hmac(sha256)")
* @treturn crypto_shash
* @raise on allocation failure
* @usage
*   local shash = require("crypto.shash")
*   local h = shash.new("sha256")
*/
static int luacrypto_shash_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_shash_class, 0, true);

	struct crypto_shash *tfm = crypto_alloc_shash(algname, 0, 0);
	if (IS_ERR(tfm)) {
		long err = PTR_ERR(tfm);
		luaL_error(L, "Failed to allocate shash transform for %s (err %ld)", algname, err);
	}

	size_t desc_size = sizeof(struct shash_desc) + crypto_shash_descsize(tfm);
	struct shash_desc *sdesc = lunatik_checkalloc(L, desc_size);
	sdesc->tfm = tfm;
	object->private = sdesc;

	return 1;
}

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

