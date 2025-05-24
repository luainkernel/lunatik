/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Crypto API for synchronous
* Random Number Generators (RNG).
*
* This module provides a `new` function to create RNG objects,
* which can then be used for generating random bytes.
*
* @module crypto_rng
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/crypto.h>
#include <crypto/rng.h>
#include <linux/err.h>
#include <linux/limits.h>
#include <linux/slab.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

static const lunatik_class_t luacrypto_rng_tfm_class;

LUNATIK_PRIVATECHECKER(luacrypto_check_rng_tfm, struct crypto_rng *);

static void luacrypto_rng_tfm_release(void *private)
{
	struct crypto_rng *tfm = (struct crypto_rng *)private;
	if (tfm && !IS_ERR(tfm)) {
		crypto_free_rng(tfm);
	}
}


/***
* RNG object methods.
* These methods are available on RNG objects created by `crypto_rng.new()`.
* @see crypto_rng.new
* @type crypto_rng
*/

/***
* Generates a specified number of random bytes, with optional seed.
* @function crypto_rng:generate
* @tparam integer num_bytes The number of random bytes to generate.
* @tparam[opt] string seed Optional seed material to mix into the RNG. If nil or omitted, no explicit seed is used.
* @treturn string A binary string containing the generated random bytes.
* @raise Error on failure (e.g., allocation error, crypto API error).
*/
static int luacrypto_rng_tfm_generate(lua_State *L) {
	struct crypto_rng *tfm = luacrypto_check_rng_tfm(L, 1);
	lua_Integer num_bytes_l = luaL_checkinteger(L, 2);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	int ret;

	luaL_argcheck(L, num_bytes_l >= 0, 2, "number of bytes must be non-negative");

	size_t num_bytes = (size_t)num_bytes_l;
	if (num_bytes == 0) {
		lua_pushlstring(L, "", 0);
		return 1;
	}

	size_t seed_len = 0;
	const char *seed_data = luaL_optlstring(L, 3, NULL, &seed_len);

	u8 *buffer = kmalloc(num_bytes, gfp);
	if (!buffer) {
		return luaL_error(L, "rng_tfm:generate: failed to allocate buffer");
	}

	ret = crypto_rng_generate(tfm, seed_data, (unsigned int)seed_len, buffer, (unsigned int)num_bytes);
	if (ret) {
		kfree(buffer);
		return luaL_error(L, "rng_tfm:generate: crypto_rng_generate failed (%d)", ret);
	}
	lua_pushlstring(L, (const char *)buffer, num_bytes);
	kfree(buffer);
	return 1;
}

/***
* Generates a specified number of random bytes.
* This function does not take an explicit seed as an argument.
* @function crypto_rng:get_bytes
* @tparam integer num_bytes The number of random bytes to generate.
* @treturn string A binary string containing the generated random bytes.
* @raise Error on failure (e.g., allocation error, crypto API error).
*/
static int luacrypto_rng_tfm_get_bytes(lua_State *L) {
	struct crypto_rng *tfm = luacrypto_check_rng_tfm(L, 1);
	lua_Integer num_bytes_l = luaL_checkinteger(L, 2);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int num_bytes_uint;
	u8 *buffer;
	int ret;

	luaL_argcheck(L, num_bytes_l >= 0, 2, "number of bytes must be non-negative");
	luaL_argcheck(L, num_bytes_l <= UINT_MAX, 2, "number of bytes exceeds UINT_MAX");
	num_bytes_uint = (unsigned int)num_bytes_l;

	if (num_bytes_uint == 0) {
		lua_pushlstring(L, "", 0);
		return 1;
	}

	buffer = kmalloc(num_bytes_uint, gfp);
	if (!buffer) {
		return luaL_error(L, "rng_tfm:get_bytes: failed to allocate buffer");
	}

	ret = crypto_rng_get_bytes(tfm, buffer, num_bytes_uint);
	if (ret) {
		kfree(buffer);
		return luaL_error(L, "rng_tfm:get_bytes: crypto_rng_get_bytes failed (%d)", ret);
	}
	lua_pushlstring(L, (const char *)buffer, num_bytes_uint);
	kfree(buffer);
	return 1;
}

/***
* Resets the RNG.
* This can be used to re-initialize the RNG, optionally with new seed material.
* @function crypto_rng:reset
* @tparam[opt] string seed Optional seed material to mix into the RNG. If nil or omitted, the RNG will reseed from its default sources.
* @raise Error on failure (e.g., crypto API error).
*/
static int luacrypto_rng_tfm_reset(lua_State *L) {
	struct crypto_rng *tfm = luacrypto_check_rng_tfm(L, 1);
	int ret;

	size_t seed_len = 0;
	const char *seed_data = luaL_optlstring(L, 2, NULL, &seed_len);

	ret = crypto_rng_reset(tfm, (const u8 *)seed_data, (unsigned int)seed_len);

	if (ret) {
		return luaL_error(L, "rng_tfm:reset: crypto_rng_reset failed (%d)", ret);
	}

	return 0;
}

/***
* Retrieves information about the RNG algorithm.
* @function crypto_rng:alg_info
* @treturn table A table containing algorithm information, e.g., `{ driver_name = "...", seedsize = num }`.
*/
static int luacrypto_rng_tfm_alg_info(lua_State *L) {
	struct crypto_rng *tfm = luacrypto_check_rng_tfm(L, 1);
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
static const luaL_Reg luacrypto_rng_tfm_mt[] = {
	{"generate", luacrypto_rng_tfm_generate},
	{"reset", luacrypto_rng_tfm_reset},
	{"get_bytes", luacrypto_rng_tfm_get_bytes},
	{"alg_info", luacrypto_rng_tfm_alg_info},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

/*** Lunatik class definition for RNG objects.
* This structure binds the C implementation (struct crypto_rng *, methods, release function)
* to the Lua object system managed by Lunatik.
*/
static const lunatik_class_t luacrypto_rng_tfm_class = {
	.name = "crypto_rng_tfm", /* Lua type name */
	.methods = luacrypto_rng_tfm_mt,
	.release = luacrypto_rng_tfm_release,
	.sleep = true,
	.pointer = true
};


/***
* Creates a new RNG object.
* This is the constructor function for the `crypto_rng` module.
* @function crypto_rng.new
* @tparam string algname The name of the RNG algorithm (e.g., "stdrng", "drbg_nopr_ctr_aes256"). Defaults to "stdrng" if nil or omitted.
* @treturn crypto_rng The new RNG object.
* @raise Error if the TFM object cannot be allocated/initialized.
* @usage
*   local rng_mod = require("crypto_rng")
*   local rng = rng_mod.new()  -- Uses default "stdrng"
*   local random_bytes = rng:generate(32)  -- Get 32 random bytes
*/
static int luacrypto_rng_new(lua_State *L) {
	const char *algname = luaL_optstring(L, 1, "stdrng");
	struct crypto_rng *tfm;
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_rng_tfm_class, 0);
	if (!object) {
		return luaL_error(L, "crypto_rng.new: failed to create RNG object");
	}

	tfm = crypto_alloc_rng(algname, 0, 0);
	if (IS_ERR(tfm)) {
		long err = PTR_ERR(tfm);
		return luaL_error(L, "failed to allocate RNG transform for %s (err %ld)", algname, err);
	}
	object->private = (void *)tfm;

	crypto_rng_reset(tfm, NULL, 0);
	return 1;
}


static const luaL_Reg luacrypto_rng_lib_funcs[] = {
	{"new", luacrypto_rng_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_rng, luacrypto_rng_lib_funcs, &luacrypto_rng_tfm_class, NULL);

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
