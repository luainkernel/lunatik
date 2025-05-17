/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
Example uses:
local crypto = require("crypto")

-- SHA-256
local hash = crypto.hash
hash("sha256", data)

-- AES-128-GCM encrypt / decrypt
local c = crypto.new("gcm(aes)")
c:setkey("0123456789abcdef")
c:setauthsize(16)
-- Encrypt:
local nonce = "\0\0\0\0\0\0\0\0\0\0\0\0"  -- 12-byte nonce, must be unique per invocation
local ciphertext, tag_len = c:encrypt(nonce, "plaintext", "myaad")
-- Decrypt:
local plaintext = c:decrypt(nonce, ciphertext, "myaad")
print(plaintext)
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/crypto.h>
#include <crypto/hash.h>
#include <crypto/aead.h>
#include <linux/err.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>
#include <linux/hex.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

// Generic hash: hash a string with a given algorithm
static int luacrypto_hash(lua_State *L)
{
	size_t datalen;
	const char *alg = luaL_checkstring(L, 1);
	const char *data = luaL_checklstring(L, 2, &datalen);

	struct crypto_shash *tfm;
	struct shash_desc *desc;
	int digestsize, ret;
	u8 *digest;
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));

	tfm = crypto_alloc_shash(alg, 0, 0);
	if (IS_ERR(tfm))
		return luaL_error(L, "failed to alloc shash tfm");

	digestsize = crypto_shash_digestsize(tfm);
	digest = kmalloc(digestsize, gfp);
	if (!digest)
	{
		crypto_free_shash(tfm);
		return luaL_error(L, "failed to alloc digest buffer");
	}

	desc = kmalloc(sizeof(*desc) + crypto_shash_descsize(tfm), gfp);
	if (!desc)
	{
		kfree(digest);
		crypto_free_shash(tfm);
		return luaL_error(L, "failed to alloc desc");
	}
	desc->tfm = tfm;

	ret = crypto_shash_digest(desc, data, datalen, digest);
	crypto_free_shash(tfm);
	kfree(desc);

	if (ret)
	{
		kfree(digest);
		return luaL_error(L, "digest failed (%d)", ret);
	}

	lua_pushlstring(L, (const char *)digest, digestsize);
	kfree(digest);
	return 1;
}

static int luacrypto_hmac(lua_State *L)
{
	size_t keylen, datalen;
	const char *alg = luaL_checkstring(L, 1);
	const char *key = luaL_checklstring(L, 2, &keylen);
	const char *data = luaL_checklstring(L, 3, &datalen);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));

	char hmac_alg[CRYPTO_MAX_ALG_NAME];
	snprintf(hmac_alg, sizeof(hmac_alg), "hmac(%s)", alg);

	struct crypto_shash *tfm = crypto_alloc_shash(hmac_alg, 0, 0);
	if (IS_ERR(tfm))
		return luaL_error(L, "failed to alloc hmac tfm");

	int ret = crypto_shash_setkey(tfm, key, keylen);
	if (ret)
	{
		crypto_free_shash(tfm);
		return luaL_error(L, "failed to set hmac key (%d)", ret);
	}

	int digestsize = crypto_shash_digestsize(tfm);
	u8 *digest = kmalloc(digestsize, gfp);
	if (!digest)
	{
		crypto_free_shash(tfm);
		return luaL_error(L, "failed to alloc digest buffer");
	}

	struct shash_desc *desc = kmalloc(sizeof(*desc) + crypto_shash_descsize(tfm), gfp);
	if (!desc)
	{
		kfree(digest);
		crypto_free_shash(tfm);
		return luaL_error(L, "failed to alloc desc");
	}
	desc->tfm = tfm;

	ret = crypto_shash_digest(desc, data, datalen, digest);
	crypto_free_shash(tfm);
	kfree(desc);

	if (ret)
	{
		kfree(digest);
		return luaL_error(L, "hmac failed (%d)", ret);
	}

	lua_pushlstring(L, (const char *)digest, digestsize);
	kfree(digest);
	return 1;
}

LUNATIK_PRIVATECHECKER(luacrypto_check, struct crypto_aead *);

/*
* crypto:setkey(key)
*
* Sets the key for the crypto transform. For example, for AES-128-GCM,
* the key length must be 16 bytes. Other algorithms may require different lengths.
*/
static int luacrypto_setkey(lua_State *L)
{
	struct crypto_aead *tfm = luacrypto_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	int ret;

	ret = crypto_aead_setkey(tfm, key, keylen);
	if (ret)
		luaL_error(L, "failed to set key (%d)", ret);

	return 1;
}

/*
* crypto:setauthsize(tagsize)
*
* Sets the size (in bytes) of the authentication tag.
*/
static int luacrypto_setauthsize(lua_State *L)
{
	struct crypto_aead *tfm = luacrypto_check(L, 1);
	int tagsize = luaL_checkinteger(L, 2);
	int ret;

	ret = crypto_aead_setauthsize(tfm, tagsize);
	if (ret)
		luaL_error(L, "failed to set authsize (%d)", ret);

	return 1;
}

/*
* crypto:encrypt(nonce, plaintext, aad)
*
* Encrypts the plaintext using the provided nonce and additional authenticated data (AAD).
* Returns two values: the ciphertext (which includes the appended authentication tag)
* and the length of the tag.
*
* The nonce and plaintext are Lua strings, and AAD is optional.
*/
static int luacrypto_encrypt(lua_State *L)
{
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	size_t iv_len, pt_len, aad_len, ct_len, authsize, iv_len_expected;
	u8 *iv_buf = NULL, *pt_buf = NULL, *aad_buf = NULL;
	struct aead_request *req = NULL;
	struct scatterlist sg[2];

	struct crypto_aead *tfm = luacrypto_check(L, 1);
	const char *iv = luaL_checklstring(L, 2, &iv_len);
	const char *plaintext = luaL_checklstring(L, 3, &pt_len);
	aad_len = 0;  // aad is optional
	const char *aad = (!lua_isnoneornil(L, 4)) ? luaL_checklstring(L, 4, &aad_len) : NULL;

	int ret;

	authsize = crypto_aead_authsize(tfm);
	iv_len_expected = crypto_aead_ivsize(tfm);
	if (iv_len != iv_len_expected)
	return luaL_error(
		L, "incorrect nonce length: expected %u, got %zu",
		iv_len_expected, iv_len
	);
	ct_len = pt_len + authsize;

	iv_buf = kmemdup(iv, iv_len, gfp);
	if (!iv_buf)
		return luaL_error(L, "failed to allocate iv buffer");
	pt_buf = kmalloc(ct_len, gfp);
	if (!pt_buf) {
		kfree(iv_buf);
		return luaL_error(L, "failed to allocate pt buffer");
	}
	if (aad_len > 0) {
		aad_buf = kmemdup(aad, aad_len, gfp);
		if (!aad_buf) {
			kfree(iv_buf);
			kfree(pt_buf);
			return luaL_error(L, "failed to allocate aad buffer");
		}
	}
	memcpy(pt_buf, plaintext, pt_len);

	req = aead_request_alloc(tfm, gfp);
	if (!req) {
		kfree(aad_buf);
		kfree(iv_buf);
		kfree(pt_buf);
		return luaL_error(L, "failed to allocate aead request");
	}

	if (aad_len > 0) {
		sg_init_table(sg, 2);
		sg_set_buf(&sg[0], aad_buf, aad_len);
		sg_set_buf(&sg[1], pt_buf, ct_len);
	} else {
		sg_init_table(sg, 1);
		sg_set_buf(&sg[0], pt_buf, ct_len);
	}

	aead_request_set_ad(req, aad_len);
	aead_request_set_callback(req, 0, NULL, NULL);
	aead_request_set_crypt(req, sg, sg, pt_len, iv_buf);
	ret = crypto_aead_encrypt(req);

	aead_request_free(req);
	kfree(aad_buf);
	kfree(iv_buf);

	if (ret) {
		kfree(pt_buf);
		return luaL_error(L, "encryption failed (%d)", ret);
	}

	lua_pushlstring(L, (const char *)pt_buf, ct_len);
	lua_pushinteger(L, authsize);
	kfree(pt_buf);
	return 2;
}

/*
* crypto:decrypt(nonce, ciphertext, aad)
*
* Decrypts the ciphertext using the provided nonce and additional authenticated data (AAD).
* The ciphertext must include the appended authentication tag.
* On success, returns the plaintext.
*/
static int luacrypto_decrypt(lua_State *L)
{
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	size_t iv_len, ct_len, aad_len, pt_len, authsize, iv_len_expected;
	u8 *iv_buf = NULL, *out_buf = NULL, *aad_buf = NULL;
	struct aead_request *req = NULL;
	struct scatterlist sg;

	struct crypto_aead *tfm = luacrypto_check(L, 1);
	const char *iv = luaL_checklstring(L, 2, &iv_len);
	const char *ciphertext = luaL_checklstring(L, 3, &ct_len);
	aad_len = 0;
	const char *aad = (!lua_isnoneornil(L, 4)) ? luaL_checklstring(L, 4, &aad_len) : NULL;
	int ret;

	iv_len_expected = crypto_aead_ivsize(tfm);
	luaL_argcheck(L, iv_len == iv_len_expected, 2, "incorrect nonce length");

	authsize = crypto_aead_authsize(tfm);
	luaL_argcheck(L, ct_len >= authsize, 3, "ciphertext too short (must include tag)");


	pt_len = ct_len - authsize;

	iv_buf = kmemdup(iv, iv_len, gfp);
	if (!iv_buf) {
		return luaL_error(L, "failed to allocate iv buffer");
	}
	out_buf = kmalloc(aad_len + ct_len, gfp);
	if (!out_buf) {
		kfree(iv_buf);
		return luaL_error(L, "failed to allocate out buffer");
	}
	if (aad_len > 0) {
		aad_buf = kmemdup(aad, aad_len, gfp);
		if (!aad_buf) {
			kfree(out_buf);
			kfree(iv_buf);
			return luaL_error(L, "failed to allocate aad buffer");
		}
	}

	// Following lines are there only for debugging purposes,
	// to understand why `decryption failed (err -22, possibly auth error)`
	char *iv_hex = kmalloc(2 * iv_len + 1, gfp);
	char *ciphertext_hex = kmalloc(2 * ct_len + 1, gfp);
	char *aad_hex = kmalloc(2 * aad_len + 1, gfp);
	bin2hex(iv_hex, iv_buf, iv_len);
	bin2hex(ciphertext_hex, ciphertext, ct_len);
	bin2hex(aad_hex, aad_buf, aad_len);
	pr_info("IV: %s, %zu\n", iv_hex, iv_len);
	kfree(iv_hex);
	pr_info("AAD: %s, %zu\n", aad_hex, aad_len);
	kfree(aad_hex);
	pr_info("CIPHERTEXT: %s, %zu\n", ciphertext_hex, ct_len);
	kfree(ciphertext_hex);

	if (aad_len > 0) {
		memcpy(out_buf, aad_buf, aad_len);
	}
	memcpy(out_buf + aad_len, ciphertext, ct_len);

	req = aead_request_alloc(tfm, gfp);
	if (!req) {
		kfree(aad_buf);
		kfree(out_buf);
		kfree(iv_buf);
		return luaL_error(L, "failed to allocate aead request");
	}

	sg_init_one(&sg, out_buf, aad_len + ct_len);

	aead_request_set_ad(req, aad_len);
	aead_request_set_callback(req, 0, NULL, NULL);
	aead_request_set_crypt(req, &sg, &sg, pt_len, iv_buf);

	ret = crypto_aead_decrypt(req);

	aead_request_free(req);
	kfree(iv_buf);
	kfree(aad_buf);

	if (ret) { /* Decryption or authentication failed */
		kfree(out_buf);
		return luaL_error(L, "decryption failed (err %d, possibly auth error)", ret);
	}

	lua_pushlstring(L, (const char *)(out_buf + aad_len), pt_len);
	kfree(out_buf);
	return 1;
}

/*
* Release callback: Called when the Lua crypto object is garbage collected.
* Frees the crypto transform.
*/
static void luacrypto_release(void *private)
{
	struct crypto_aead *tfm = (struct crypto_aead *)private;
	if (tfm)
	crypto_free_aead(tfm);
}

/*
* Lua object methods for the crypto API.
*/
static const luaL_Reg luacrypto_mt[] = {
	{"setkey", luacrypto_setkey},
	{"setauthsize", luacrypto_setauthsize},
	{"encrypt", luacrypto_encrypt},
	{"decrypt", luacrypto_decrypt},
	{"close", lunatik_closeobject},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_class = {
	.name = "crypto",
	.methods = luacrypto_mt,
	.release = luacrypto_release,
	.sleep = true,
	.pointer = true,
};

/*
* crypto.new(algname)
*
* Creates a new crypto object. The argument algname is a string, e.g., "gcm(aes)",
* that specifies the algorithm. This design is generic so that additional algorithms
* and modes can be supported.
*/
static int luacrypto_new(lua_State *L)
{
	struct crypto_aead *tfm;
	const char *algname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_class, 0);
	if (!object)
		luaL_error(L, "failed to allocate object");
	tfm = crypto_alloc_aead(algname, 0, 0);
	if (IS_ERR(tfm)) {
		luaL_error(
			L, "failed to allocate transform for %s (%d)",
			algname, PTR_ERR(tfm)
		);
	}

	object->private = tfm;
	return 1;
}

static const luaL_Reg luacrypto_lib[] = {
	{"hash", luacrypto_hash},
	{"hmac", luacrypto_hmac},
	{"new", luacrypto_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto, luacrypto_lib, &luacrypto_class, NULL);

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
MODULE_AUTHOR("jperon <cataclop@hotmail.com>");
