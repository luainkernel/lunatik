/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to the Linux Crypto API.
* Crypto objects are created in a process runtime alone: in a softirq or hardirq runtime a
* constructor raises "'crypto_shash': process-context class in interrupt-context runtime", naming
* its class. Errors are raised as errno names: "ENOENT" for an unknown algorithm, "EINVAL" for a
* wrong IV, key or state length or a block cipher input that is not a multiple of `blocksize()`,
* "EBADMSG" for an AEAD tag mismatch, "ENOMEM" when the kernel cannot allocate the transform, and
* "not enough memory" when the binding cannot allocate its own state, its output or the copy of its
* input.
* @module crypto
*/

/***
* Creates a synchronous hash transform.
* @function shash
* @tparam string algname algorithm name (e.g., "sha256", "hmac(sha256)")
* @treturn crypto_shash
* @raise "ENOENT" for an unknown algorithm, "ENOMEM" or "not enough memory" on allocation
*   failure
* @usage
*   local shash = require("crypto").shash
*   local h = shash("sha256")
*/

/***
* Creates a symmetric-key cipher transform.
* Only a synchronous implementation is chosen: an asynchronous one, such as a hardware engine's
* or a `cryptd(...)` instance, is passed over.
* @function skcipher
* @tparam string algname algorithm name (e.g., "cbc(aes)", "ctr(aes)")
* @treturn crypto_skcipher
* @raise "ENOENT" for an unknown algorithm or one no synchronous implementation serves ("EEXIST"
*   on 6.12 and later for a template whose instance is asynchronous, such as `cryptd(...)`),
*   "ENOMEM" or "not enough memory" on allocation failure
* @usage
*   local skcipher = require("crypto").skcipher
*   local cipher = skcipher("cbc(aes)")
*/

/***
* Creates an AEAD cipher transform.
* Only a synchronous implementation is chosen: an asynchronous one, such as a hardware engine's
* or a `cryptd(...)` instance, is passed over.
* @function aead
* @tparam string algname algorithm name (e.g., "gcm(aes)", "ccm(aes)")
* @treturn crypto_aead
* @raise "ENOENT" for an unknown algorithm or one no synchronous implementation serves ("EEXIST"
*   on 6.12 and later for a template whose instance is asynchronous, such as `cryptd(...)`),
*   "ENOMEM" or "not enough memory" on allocation failure
* @usage
*   local aead = require("crypto").aead
*   local cipher = aead("gcm(aes)")
*/

/***
* Creates a random number generator.
* @function rng
* @tparam[opt="stdrng"] string algname algorithm name
* @treturn crypto_rng
* @raise "ENOENT" for an unknown algorithm, "ENOMEM" or "not enough memory" on allocation
*   failure, or the errno of the seeding it runs at creation
* @usage
*   local rng = require("crypto").rng
*   local r = rng()
*/

/***
* Creates a compression transform. Absent on 6.15 and later, whose kernel has no synchronous
* compression API.
* @function comp
* @tparam string algname algorithm name (e.g., "lz4", "deflate")
* @treturn crypto_comp
* @raise "ENOENT" for an unknown algorithm, "ENOMEM" or "not enough memory" on allocation
*   failure
* @usage
*   local comp = require("crypto").comp
*   local c = comp("lz4")
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include "luacrypto.h"

char *luacrypto_newbuffer(lua_State *L, size_t size)
{
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L)) | __GFP_NOWARN; /* Lua raises on a NULL */
	return (char *)lunatik_checknull(L, kmalloc(size, gfp)); /* a scatterlist maps linear memory */
}

static const luaL_Reg luacrypto_lib[] = {
	{"shash", luacrypto_shash_new},
	{"skcipher", luacrypto_skcipher_new},
	{"aead", luacrypto_aead_new},
	{"rng", luacrypto_rng_new},
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))
	{"comp", luacrypto_comp_new},
#endif
	{NULL, NULL}
};

static const lunatik_class_t *luacrypto_classes[] = {
	&luacrypto_shash_class,
	&luacrypto_skcipher_class,
	&luacrypto_aead_class,
	&luacrypto_rng_class,
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))
	&luacrypto_comp_class,
#endif
	NULL
};

LUNATIK_NEWLIB(crypto, luacrypto_lib, luacrypto_classes);

static int __init luacrypto_init(void)
{
	return 0;
}

static void __exit luacrypto_exit(void)
{
}

module_init(luacrypto_init);
module_exit(luacrypto_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("jperon <cataclop@hotmail.com>");
MODULE_DESCRIPTION("Lunatik Linux Crypto API interface");

