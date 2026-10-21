/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to public key signature verification.
* A verifier takes a public key with `setpubkey`, then answers whether a signature over a digest
* verifies. It does not sign.
* @classmod crypto_sig
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/sig.h>
#include <linux/err.h>
#include <linux/limits.h>

#include "luacrypto.h"

/* the most asn1_ber_decoder reads; on 6.12 and earlier crypto_akcipher_sync_prep copies both strings at once */
#define LUACRYPTO_SIG_MAXLEN	U16_MAX

#define luacrypto_sig_needskey(tfm)	(crypto_tfm_get_flags(crypto_sig_tfm(tfm)) & CRYPTO_TFM_NEED_KEY)
#define luacrypto_sig_setneedkey(tfm)	crypto_tfm_set_flags(crypto_sig_tfm(tfm), CRYPTO_TFM_NEED_KEY)
#define luacrypto_sig_clearneedkey(tfm)	crypto_tfm_clear_flags(crypto_sig_tfm(tfm), CRYPTO_TFM_NEED_KEY)

LUNATIK_PRIVATECHECKER(luacrypto_sig_check, struct crypto_sig *, &luacrypto_sig_class);

/* crypto_sig_maxsize dereferences the key, and verify answers its absence differently by algorithm */
LUNATIK_PRIVATECHECKER(luacrypto_sig_checkkeyed, struct crypto_sig *, &luacrypto_sig_class,
	if (luacrypto_sig_needskey(private))
		lunatik_throw(L, -ENOKEY);
);

LUACRYPTO_RELEASER(sig, struct crypto_sig, crypto_free_sig);

#define luacrypto_sig_isfailure(ret)	((ret) == -ENOMEM || (ret) == -ENOSYS)

/***
* Sets the public key, in the algorithm's own encoding: ECDSA takes the uncompressed point,
* `0x04 || x || y`, 65 bytes for P-256; RSA takes the DER `RSAPublicKey`,
* `SEQUENCE { n INTEGER, e INTEGER }`. A key that fails leaves the verifier without one.
* @function setpubkey
* @tparam string key
* @raise "EINVAL" for a key the algorithm refuses, such as a compressed or off-curve point, a
*   point of another length or a modulus of a size RSA does not take, "EBADMSG" for a DER key that
*   does not parse
*/
static int luacrypto_sig_setpubkey(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);

	luacrypto_sig_setneedkey(tfm);
	lunatik_try(L, crypto_sig_set_pubkey, tfm, key, keylen);
	luacrypto_sig_clearneedkey(tfm);
	return 0;
}

/***
* Verifies a signature over a digest.
* The answer is the kernel's verdict on the two strings, so a signature a peer sent raises only
* for a length out of bounds. ECDSA pads or truncates a digest of another size than the curve's.
* @function verify
* @tparam string signature the signature in the algorithm's encoding, of at most 65535 bytes
* @tparam string digest the digest the signature was made over, of 1 to 65535 bytes
* @treturn boolean true when the signature verifies, or false and the errno's name:
*   "EKEYREJECTED" for a signature that does not verify the digest, "EBADMSG" for one that does
*   not parse, "EINVAL" for a length the algorithm cannot take or a DER integer longer than the
*   curve
* @raise "ENOKEY" before a `setpubkey` succeeds, "ENOSYS" for an algorithm that does not verify,
*   such as `rsa` on 6.12 and earlier, "ENOMEM", and "out of bounds" for a string of a length out of
*   bounds
*/
static int luacrypto_sig_verify(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_checkkeyed(L, 1);
	size_t siglen, digestlen;
	const char *signature = luaL_checklstring(L, 2, &siglen);
	const char *digest = luaL_checklstring(L, 3, &digestlen);

	lunatik_checkbounds(L, 2, siglen, 0, LUACRYPTO_SIG_MAXLEN);
	/* v6.12 and earlier: pkcs1pad_verify WARNs on an empty digest */
	lunatik_checkbounds(L, 3, digestlen, 1, LUACRYPTO_SIG_MAXLEN);

	int ret = crypto_sig_verify(tfm, signature, siglen, digest, digestlen);
	if (ret == 0) {
		lua_pushboolean(L, true);
		return 1;
	}
	if (luacrypto_sig_isfailure(ret))
		lunatik_throw(L, ret);
	lua_pushboolean(L, false);
	lunatik_pusherrname(L, ret);
	return 2;
}

/***
* Returns the size in bytes the kernel gives for a signature under the key: the key's for RSA,
* the DER bound for `x962(...)` and twice the key's for `p1363(...)`. On 6.12 and earlier ECDSA
* answers the key's size, 32 for P-256, which a DER signature exceeds.
* @function maxsize
* @treturn integer
* @raise "ENOKEY" before a `setpubkey` succeeds
*/
LUNATIK_INTEGERGETTER(luacrypto_sig_maxsize, luacrypto_sig_checkkeyed, crypto_sig_maxsize(private));

/***
* Returns the driver-independent name of the algorithm the transform was allocated with.
* @function algname
* @treturn string
*/
static int luacrypto_sig_algname(lua_State *L)
{
	struct crypto_sig *tfm = luacrypto_sig_check(L, 1);
	lua_pushstring(L, crypto_tfm_alg_name(crypto_sig_tfm(tfm)));
	return 1;
}

/***
* Releases the transform.
* A to-be-closed variable holding the object releases it the same way. Calling it again does
* nothing, and every other method raises "closed object" afterwards.
* @function close
* @treturn nil
*/
static const luaL_Reg luacrypto_sig_mt[] = {
	{"algname", luacrypto_sig_algname},
	{"setpubkey", luacrypto_sig_setpubkey},
	{"verify", luacrypto_sig_verify},
	{"maxsize", luacrypto_sig_maxsize},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"close", lunatik_closeobject},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_sig_class = {
	.name = "crypto.sig",
	.methods = luacrypto_sig_mt,
	.release = luacrypto_sig_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
	.owner = THIS_MODULE,
};

int luacrypto_sig_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_sig_class, 0, LUNATIK_OPT_NONE);

	/* v6.13: crypto_alloc_sig also matches an akcipher, whose ops it then calls as a sig_alg's */
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 13, 0)) && (LINUX_VERSION_CODE < KERNEL_VERSION(6, 14, 0))
	if (!crypto_has_alg(algname, CRYPTO_ALG_TYPE_SIG, CRYPTO_ALG_TYPE_MASK))
		lunatik_throw(L, -ENOENT);
#endif
	struct crypto_sig *tfm = crypto_alloc_sig(algname, 0, 0);

	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));

	luacrypto_sig_setneedkey(tfm);
	object->private = tfm;
	return 1;
}

