/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to synchronous Random Number Generators (RNG).
* @classmod crypto_rng
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/rng.h>
#include <linux/err.h>
#include <linux/limits.h>
#include <linux/slab.h>

#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_rng_check, struct crypto_rng *, &luacrypto_rng_class);

LUACRYPTO_RELEASER(rng, struct crypto_rng, crypto_free_rng);

/***
* Generates random bytes.
* The optional string reaches the algorithm as additional input for this call, which drbg mixes
* into its output. It does not reseed: `reset` does.
* @function generate
* @tparam integer n number of bytes to generate
* @tparam[opt] string additional additional input
* @treturn string random bytes
* @raise on generation failure
*/
static int luacrypto_rng_generate(lua_State *L)
{
	struct crypto_rng *tfm = luacrypto_rng_check(L, 1);
	unsigned int num_bytes = (unsigned int)lunatik_checkinteger(L, 2, 1, UINT_MAX);

	size_t seed_len = 0;
	const char *seed_data = luaL_optlstring(L, 3, NULL, &seed_len);

	luaL_Buffer B;
	char *buffer = luaL_buffinitsize(L, &B, num_bytes);

	lunatik_try(L, crypto_rng_generate, tfm, seed_data, (unsigned int)seed_len, (u8 *)buffer, num_bytes);
	luaL_pushresultsize(&B, num_bytes);
	return 1;
}

/***
* Reseeds the RNG.
* Without a seed, the kernel draws one of `seedsize()` random bytes.
* @function reset
* @tparam[opt] string seed
* @raise on reseed failure
*/
static int luacrypto_rng_reset(lua_State *L)
{
	struct crypto_rng *tfm = luacrypto_rng_check(L, 1);
	size_t seed_len = 0;
	const char *seed_data = luaL_optlstring(L, 2, NULL, &seed_len);
	if (!seed_data)
		seed_len = crypto_rng_seedsize(tfm);
	lunatik_try(L, crypto_rng_reset, tfm, (const u8 *)seed_data, (unsigned int)seed_len);
	return 0;
}

/***
* Generates random bytes with no additional input.
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
* Returns the size in bytes of the seed `reset` takes, 0 for an algorithm that requires none.
* @function seedsize
* @treturn integer
*/
static int luacrypto_rng_seedsize(lua_State *L)
{
	struct crypto_rng *tfm = luacrypto_rng_check(L, 1);
	lua_pushinteger(L, crypto_rng_seedsize(tfm));
	return 1;
}

/***
* Returns the driver-independent name of the algorithm the transform was allocated with.
* @function algname
* @treturn string
*/
static int luacrypto_rng_algname(lua_State *L)
{
	struct crypto_rng *tfm = luacrypto_rng_check(L, 1);
	lua_pushstring(L, crypto_tfm_alg_name(crypto_rng_tfm(tfm)));
	return 1;
}

/***
* Releases the transform.
* A to-be-closed variable holding the object releases it the same way. Calling it again does
* nothing, and every other method raises "closed object" afterwards.
* @function close
* @treturn nil
*/
static const luaL_Reg luacrypto_rng_mt[] = {
	{"algname", luacrypto_rng_algname},
	{"generate", luacrypto_rng_generate},
	{"reset", luacrypto_rng_reset},
	{"getbytes", luacrypto_rng_getbytes},
	{"seedsize", luacrypto_rng_seedsize},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"close", lunatik_closeobject},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_rng_class = {
	.name = "crypto.rng",
	.methods = luacrypto_rng_mt,
	.release = luacrypto_rng_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
	.owner = THIS_MODULE,
};

int luacrypto_rng_new(lua_State *L)
{
	const char *algname = luaL_optstring(L, 1, "stdrng");
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_rng_class, 0, LUNATIK_OPT_NONE);
	struct crypto_rng *tfm = crypto_alloc_rng(algname, 0, 0);

	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));

	object->private = tfm;
	lunatik_try(L, crypto_rng_reset, tfm, NULL, crypto_rng_seedsize(tfm));
	return 1;
}

