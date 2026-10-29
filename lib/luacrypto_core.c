/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to the Linux Crypto API.
* Crypto objects are created in a process runtime alone: in a softirq or hardirq runtime a
* constructor raises "'crypto.shash': process-context class in interrupt-context runtime", naming
* its class. Errors are raised as errno names: "ENOENT" for an unknown algorithm, "EINVAL" for a
* wrong IV, key or state length or a block cipher input that is not a multiple of `blocksize()`,
* and on 6.12 and later for a name whose template refuses the type the constructor asks for, such
* as `shash("cbc(aes)")`, which 6.11 and earlier answer with "ENOENT",
* "ENOMEM" when the kernel cannot allocate the transform, "ENOKEY" for a signature verifier used
* before its key is set, and
* "not enough memory" when the binding cannot allocate its own state, its output or the copy of its
* input. An AEAD message that does not authenticate is no error: `decrypt` answers nil and
* "EBADMSG" for it, and a signature that does not verify is none either: `verify` answers false and
* the errno's name.
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
* Creates a random number generator and seeds it as `reset` does without a seed.
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
* Creates a signature verifier.
* The name is the kernel's, which differs by release for a DER or a PKCS#1 v1.5 signature: ECDSA
* over an X9.62 DER signature is `x962(ecdsa-nist-p256)` on 6.13 and later and `ecdsa-nist-p256` on
* 6.12 and earlier, the curve one of `p192`, `p256`, `p384`, and `p521` from 6.10; RSA PKCS#1 v1.5
* is `pkcs1(rsa,sha256)` on 6.13 and later and `pkcs1pad(rsa,sha256)` on 6.12 and earlier. On 6.13
* and later `p1363(ecdsa-nist-p256)` takes r and s concatenated big-endian, each of the key's size,
* and the bare `ecdsa-nist-p256` is the kernel's raw form, which takes r and s in the kernel's own
* digits and answers false and "EINVAL" to a DER or a P1363 signature. A script that runs on both
* sides tries the newer name first and takes "ENOENT" as the cue for the older one.
* The module links `crypto_alloc_sig`, which `CONFIG_CRYPTO_SIG2` builds on every kernel that has
* a signature algorithm.
* @function sig
* @tparam string algname algorithm name (e.g., "x962(ecdsa-nist-p256)", "pkcs1(rsa,sha256)")
* @treturn crypto_sig
* @raise "ENOENT" for an unknown algorithm, or one the kernel serves only for encryption, such as
*   `rsa` on 6.13 and later, "EINVAL" for a name its template refuses, such as
*   `pkcs1pad(rsa,sha256)` on 6.14 and later, whose template serves only encryption, where 6.11 and
*   earlier and 6.13 raise "ENOENT", "ENOMEM" or "not enough memory" on allocation failure
* @usage
*   local sig = require("crypto").sig
*   local function verifier(name, older)
*     local ok, v = pcall(sig, name)
*     if ok then
*       return v
*     end
*     assert(v == "ENOENT", v)
*     return sig(older)
*   end
*   local v = verifier("x962(ecdsa-nist-p256)", "ecdsa-nist-p256")
*   v:setpubkey(point)
*   local ok, err = v:verify(signature, digest)
*/

/***
* Creates an asynchronous compression transform.
* @function acompress
* @tparam string algname algorithm name (e.g., "lz4", "deflate")
* @treturn crypto_acompress
* @raise "ENOENT" for an unknown algorithm, "ENOMEM" or "not enough memory" on allocation
*   failure
* @usage
*   local acompress = require("crypto").acompress
*   local tfm = acompress("lz4")
*   local req = tfm:request()
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
	{"acompress", luacrypto_acompress_new},
	{"rng", luacrypto_rng_new},
	{"sig", luacrypto_sig_new},
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))
	{"comp", luacrypto_comp_new},
#endif
	{NULL, NULL}
};

static const lunatik_class_t *luacrypto_classes[] = {
	&luacrypto_shash_class,
	&luacrypto_skcipher_class,
	&luacrypto_aead_class,
	&luacrypto_acompress_class,
	&luacrypto_acompress_req_class,
	&luacrypto_rng_class,
	&luacrypto_sig_class,
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

