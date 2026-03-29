/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to message digest (hash) algorithms.
* @classmod crypto_shash
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/hash.h>
#include <linux/err.h>
#include <linux/slab.h>

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
* Sets the key.
* @function setkey
* @tparam string key
* @raise on failure
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
* Computes the digest in a single call.
* @function digest
* @tparam string data
* @treturn string digest bytes
* @raise on failure
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
* Initializes the hash state.
* @function init
* @raise on failure
*/
static int luacrypto_shash_init_mt(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);

	lunatik_try(L, crypto_shash_init, sdesc);
	return 0;
}

/***
* Feeds data into the hash.
* @function update
* @tparam string data
* @raise on failure
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
* @raise on failure
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
* Feeds final data and returns the digest.
* @function finup
* @tparam string data
* @treturn string digest bytes
* @raise on failure
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
* Restores a hash state.
* @function import
* @tparam string state blob from `export()`
* @raise on failure
*/
static int luacrypto_shash_import(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	size_t statelen;
	const char *state = luaL_checklstring(L, 2, &statelen);
	unsigned int expected_statesize = crypto_shash_statesize(sdesc->tfm);
	if (statelen != expected_statesize)
		lunatik_throw(L, -EINVAL);
	lunatik_try(L, crypto_shash_import, sdesc, state);
	return 0;
}

static int luacrypto_shash_algname(lua_State *L)
{
	struct shash_desc *sdesc = luacrypto_shash_check(L, 1);
	lua_pushstring(L, crypto_tfm_alg_name(crypto_shash_tfm(sdesc->tfm)));
	return 1;
}

static const luaL_Reg luacrypto_shash_mt[] = {
	{"algname", luacrypto_shash_algname},
	{"digestsize", luacrypto_shash_digestsize},
	{"setkey", luacrypto_shash_setkey},
	{"digest", luacrypto_shash_digest},
	{"init", luacrypto_shash_init_mt},
	{"update", luacrypto_shash_update},
	{"final", luacrypto_shash_final},
	{"finup", luacrypto_shash_finup},
	{"export", luacrypto_shash_export},
	{"import", luacrypto_shash_import},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_shash_class = {
	.name = "crypto_shash",
	.methods = luacrypto_shash_mt,
	.release = luacrypto_shash_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

/***
* Creates a new SHASH object.
* @function new
* @tparam string algname algorithm (e.g., "sha256")
* @treturn crypto_shash
* @usage
*   local shash = require("crypto").shash
*   local h = shash("sha256")
*/
int luacrypto_shash_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);
	struct crypto_shash *tfm = crypto_alloc_shash(algname, 0, 0);
	size_t desc_size;
	struct shash_desc *sdesc;
	lunatik_object_t *object;

	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));

	desc_size = sizeof(struct shash_desc) + crypto_shash_descsize(tfm);
	sdesc = lunatik_malloc(L, desc_size);
	if (!sdesc) {
		crypto_free_shash(tfm);
		lunatik_enomem(L);
	}
	sdesc->tfm = tfm;

	object = lunatik_newobject(L, &luacrypto_shash_class, 0, LUNATIK_OPT_NONE);
	object->private = sdesc;
	return 1;
}

