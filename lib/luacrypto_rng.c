/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to synchronous Random Number Generators (RNG).
* @module crypto.rng
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/rng.h>
#include <linux/err.h>
#include <linux/limits.h>
#include <linux/slab.h>

#include <lunatik.h>

#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_rng_check, struct crypto_rng *);

LUACRYPTO_RELEASER(rng, struct crypto_rng, crypto_free_rng);

/***
* Generates random bytes, optionally reseeding first.
* @function generate
* @tparam integer n number of bytes to generate
* @tparam[opt] string seed optional seed data
* @treturn string random bytes
* @raise on generation failure
*/
static int luacrypto_rng_generate(lua_State *L)
{
	struct crypto_rng *tfm = luacrypto_rng_check(L, 1);
	unsigned int num_bytes = (unsigned int)lunatik_checkinteger(L, 2, 1, UINT_MAX);

	size_t seed_len = 0;
	const char *seed_data = lua_tolstring(L, 3, &seed_len);

	luaL_Buffer B;
	char *buffer = luaL_buffinitsize(L, &B, num_bytes);

	lunatik_try(L, crypto_rng_generate, tfm, seed_data, (unsigned int)seed_len, (u8 *)buffer, num_bytes);
	luaL_pushresultsize(&B, num_bytes);
	return 1;
}

/***
* Reseeds the RNG.
* @function reset
* @tparam string seed
* @raise on reseed failure
*/
static int luacrypto_rng_reset(lua_State *L)
{
	struct crypto_rng *tfm = luacrypto_rng_check(L, 1);
	size_t seed_len = 0;
	const char *seed_data = luaL_tolstring(L, 2, &seed_len);
	lunatik_try(L, crypto_rng_reset, tfm, (const u8 *)seed_data, (unsigned int)seed_len);
	return 0;
}

/***
* Generates random bytes without reseeding.
* @function getbytes
* @tparam integer n number of bytes to generate
* @treturn string random bytes
* @raise on generation failure
*/
static int luacrypto_rng_getbytes(lua_State *L)
{
	struct crypto_rng *tfm = luacrypto_rng_check(L, 1);
	unsigned int num_bytes = (unsigned int)lunatik_checkinteger(L, 2, 1, UINT_MAX);

	luaL_Buffer B;
	u8 *buffer = (u8 *)luaL_buffinitsize(L, &B, num_bytes);

	lunatik_try(L, crypto_rng_get_bytes, tfm, (u8 *)buffer, num_bytes);
	luaL_pushresultsize(&B, num_bytes);
	return 1;
}

/***
* Returns algorithm information.
* @function info
* @treturn table with fields `driver_name` (string) and `seedsize` (integer)
*/
static int luacrypto_rng_info(lua_State *L)
{
	struct crypto_rng *tfm = luacrypto_rng_check(L, 1);
	const struct rng_alg *alg = crypto_rng_alg(tfm);

	lua_createtable(L, 0, 2);

	lua_pushstring(L, alg->base.cra_driver_name);
	lua_setfield(L, -2, "driver_name");

	lua_pushinteger(L, alg->seedsize);
	lua_setfield(L, -2, "seedsize");
	return 1;
}

static const luaL_Reg luacrypto_rng_mt[] = {
	{"generate", luacrypto_rng_generate},
	{"reset", luacrypto_rng_reset},
	{"getbytes", luacrypto_rng_getbytes},
	{"info", luacrypto_rng_info},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_rng_class = {
	.name = "crypto_rng",
	.methods = luacrypto_rng_mt,
	.release = luacrypto_rng_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

/***
* Creates a new RNG object.
* @function new
* @tparam string algname algorithm name (e.g., "stdrng")
* @treturn crypto_rng
* @raise on allocation failure
* @usage
*   local rng = require("crypto.rng")
*   local r = rng.new("stdrng")
*/
static int luacrypto_rng_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_rng_class, 0, true);

	struct crypto_rng *tfm = crypto_alloc_rng(algname, 0, 0);
	if (IS_ERR(tfm)) {
		long err = PTR_ERR(tfm);
		luaL_error(L, "Failed to allocate rng transform for %s (err %ld)", algname, err);
	}
	lunatik_try(L, crypto_rng_reset, tfm, NULL, 0);
	object->private = tfm;

	return 1;
}

static const luaL_Reg luacrypto_rng_lib[] = {
	{"new", luacrypto_rng_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_rng, luacrypto_rng_lib, &luacrypto_rng_class, NULL);

static int __init luacrypto_rng_init(void)
{
	return 0;
}

static void __exit luacrypto_rng_exit(void)
{
}

module_init(luacrypto_rng_init);
module_exit(luacrypto_rng_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("jperon <cataclop@hotmail.com>");
MODULE_DESCRIPTION("Lunatik low-level Linux Crypto API interface (RNG)");

