/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to the Linux Crypto API asymmetric signature subsystem
* (`crypto_sig_*`). Modern replacement for the verify/sign paths that used
* to live under `crypto_akcipher_*` before kernel 6.10.
* @classmod crypto_sig
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include "luacrypto.h"

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 10, 0))

#include <crypto/sig.h>
#include <linux/err.h>
#include <linux/slab.h>

LUNATIK_PRIVATECHECKER(luacrypto_sig_check, struct crypto_sig *);

LUACRYPTO_RELEASER(sig, struct crypto_sig, crypto_free_sig);

/***
* Returns the key size in bits.
* @function keysize
* @treturn integer
*/
static int luacrypto_sig_keysize(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	lua_pushinteger(L, crypto_sig_keysize(tfm));
	return 1;
}

/***
* Returns the maximum signature size in bytes.
* @function maxsize
* @treturn integer
*/
static int luacrypto_sig_maxsize(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	lua_pushinteger(L, crypto_sig_maxsize(tfm));
	return 1;
}

/***
* Returns the maximum supported digest size in bytes.
* @function digestsize
* @treturn integer
*/
static int luacrypto_sig_digestsize(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	lua_pushinteger(L, crypto_sig_digestsize(tfm));
	return 1;
}

/***
* Sets the public key. For RSA the buffer must be the PKCS#1 DER encoding of
* `RSAPublicKey ::= SEQUENCE { n INTEGER, e INTEGER }` — *not* the PEM
* SubjectPublicKeyInfo. Convert from PEM with:
*   openssl rsa -pubin -RSAPublicKey_out -outform DER -in pub.pem -out pub.der
* @function setpubkey
* @tparam string der DER-encoded public key
* @raise on parse or key-size failure
*/
static int luacrypto_sig_setpubkey(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_try(L, crypto_sig_set_pubkey, tfm, key, keylen);
	return 0;
}

/***
* Sets the private key (DER-encoded RSAPrivateKey for RSA).
* @function setprivkey
* @tparam string der
* @raise on parse failure
*/
static int luacrypto_sig_setprivkey(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_try(L, crypto_sig_set_privkey, tfm, key, keylen);
	return 0;
}

/***
* Verifies a signature against a pre-computed message digest. Callers compute
* the digest themselves (e.g. via `crypto.shash("sha256"):digest(msg)`) — the
* kernel sig API expects the hash, not the raw message.
* @function verify
* @tparam string signature
* @tparam string digest pre-computed message digest
* @treturn boolean true on a valid signature, false otherwise
*/
static int luacrypto_sig_verify(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	size_t siglen, digestlen;
	const char *sig = luaL_checklstring(L, 2, &siglen);
	const char *digest = luaL_checklstring(L, 3, &digestlen);
	int err = crypto_sig_verify(tfm, sig, siglen, digest, digestlen);
	lua_pushboolean(L, err == 0);
	return 1;
}

/***
* Signs a pre-computed message digest. Returns the raw signature bytes.
* Only useful when a private key has been set via `setprivkey`.
* @function sign
* @tparam string digest pre-computed message digest
* @treturn string signature
* @raise on signing failure
*/
static int luacrypto_sig_sign(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	size_t digestlen;
	const char *digest = luaL_checklstring(L, 2, &digestlen);
	unsigned int sigsize = crypto_sig_maxsize(tfm);
	luaL_Buffer B;
	void *sig_buf = luaL_buffinitsize(L, &B, sigsize);
	int written = crypto_sig_sign(tfm, digest, digestlen, sig_buf, sigsize);
	if (written < 0)
		lunatik_throw(L, written);
	luaL_pushresultsize(&B, written);
	return 1;
}

static int luacrypto_sig_algname(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	lua_pushstring(L, crypto_tfm_alg_name(crypto_sig_tfm(tfm)));
	return 1;
}

static const luaL_Reg luacrypto_sig_mt[] = {
	{"algname", luacrypto_sig_algname},
	{"keysize", luacrypto_sig_keysize},
	{"maxsize", luacrypto_sig_maxsize},
	{"digestsize", luacrypto_sig_digestsize},
	{"setpubkey", luacrypto_sig_setpubkey},
	{"setprivkey", luacrypto_sig_setprivkey},
	{"verify", luacrypto_sig_verify},
	{"sign", luacrypto_sig_sign},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_sig_class = {
	.name = "crypto_sig",
	.methods = luacrypto_sig_mt,
	.release = luacrypto_sig_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

/***
* Creates a new asymmetric signature object.
* @function new
* @tparam string algname kernel-registered signature algorithm
*   (e.g. `"pkcs1(rsa,sha256)"`, `"ecdsa-nist-p256"`)
* @treturn crypto_sig
* @raise on allocation or unknown algorithm
* @usage
*   local crypto = require("crypto")
*   local s = crypto.sig("pkcs1(rsa,sha256)")
*   s:setpubkey(rsapubkey_der)
*   local digest = crypto.shash("sha256"):digest(message)
*   local ok = s:verify(signature, digest)
*/
int luacrypto_sig_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);
	struct crypto_sig *tfm = crypto_alloc_sig(algname, 0, 0);
	lunatik_object_t *object;

	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));

	object = lunatik_newobject(L, &luacrypto_sig_class, 0, LUNATIK_OPT_NONE);
	object->private = tfm;
	return 1;
}

#endif /* LINUX_VERSION_CODE >= 6.10 */

