/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Crypto API for synchronous
* Random Number Generators (RNG).
*
* This module provides a `new` function to create RNG objects,
* which can then be used for generating random bytes.
*
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

LUACRYPTO_RELEASER(rng, struct crypto_rng, crypto_free_rng, NULL);

/***
* RNG object methods.
* These methods are available on RNG objects created by `crypto_rng.new()`.
* @see new
* @type RNG
*/

/***
* Generates a specified number of random bytes, with optional seed.
* @function generate
* @tparam integer num_bytes The number of random bytes to generate.
* @tparam[opt] string seed Optional seed material to mix into the RNG. If nil or omitted, no explicit seed is used.
* @treturn string A binary string containing the generated random bytes.
* @raise Error on failure (e.g., allocation error, crypto API error).
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
* Generates a specified number of random bytes.
* This function does not take an explicit seed as an argument.
* @function getbytes
* @tparam integer num_bytes The number of random bytes to generate.
* @treturn string A binary string containing the generated random bytes.
* @raise Error on failure (e.g., allocation error, crypto API error).
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
* Resets the RNG.
* This can be used to re-initialize the RNG, optionally with new seed material.
* @function reset
* @tparam[opt] string seed Optional seed material to mix into the RNG. If nil or omitted, the RNG will reseed from its default sources.
* @raise Error on failure (e.g., crypto API error).
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
* Retrieves information about the RNG algorithm.
* @function info
* @treturn table A table containing algorithm information, e.g., `{ driver_name = "...", seedsize = num }`.
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

/*** Lua C methods for the RNG object.
* Includes cryptographic operations and Lunatik metamethods.
* The `__close` method is important for explicit resource cleanup.
* @see crypto_rng
* @see lunatik_closeobject
*/
static const luaL_Reg luacrypto_rng_mt[] = {
	{"generate", luacrypto_rng_generate},
	{"reset", luacrypto_rng_reset},
	{"getbytes", luacrypto_rng_getbytes},
	{"info", luacrypto_rng_info},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

/*** Lunatik class definition for RNG objects.
* This structure binds the C implementation (struct crypto_rng *, methods, release function)
* to the Lua object system managed by Lunatik.
*/
static const lunatik_class_t luacrypto_rng_class = {
	.name = "crypto_rng", /* Lua type name */
	.methods = luacrypto_rng_mt,
	.release = luacrypto_rng_release,
	.sleep = true,
	.shared = true,
	.pointer = true,
};

static inline void *luacrypto_rng_randomize(lua_State *L, void *data)
{
	struct crypto_rng *tfm = (struct crypto_rng *)data;
	lunatik_try(L, crypto_rng_reset, tfm, NULL, 0);
	return data;
}

/***
* Creates a new RNG object.
* This is the constructor function for the `crypto_rng` module.
* @function new
* @tparam string algname The name of the RNG algorithm (e.g., "stdrng", "drbg_nopr_ctr_aes256"). Defaults to "stdrng" if nil or omitted.
* @treturn crypto_rng The new RNG object.
* @raise Error if the TFM object cannot be allocated/initialized.
* @usage
*   local rng_mod = require("crypto.rng")
*   local rng = rng_mod.new()  -- Uses default "stdrng"
*   local random_bytes = rng:generate(32)  -- Get 32 random bytes
* @within rng
*/
LUACRYPTO_NEW(rng, struct crypto_rng, crypto_alloc_rng, luacrypto_rng_class, luacrypto_rng_randomize);

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

