/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to AEAD (Authenticated Encryption with Associated Data) ciphers.
* @module crypto.aead
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/aead.h>
#include <linux/err.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>

#include <lunatik.h>

#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_aead_check, struct crypto_aead *);

LUACRYPTO_RELEASER(aead, struct crypto_aead, crypto_free_aead);

/***
* Sets the cipher key.
* @function setkey
* @tparam string key
* @raise on invalid key length or algorithm error
*/
static int luacrypto_aead_setkey(lua_State *L)
{
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_try(L, crypto_aead_setkey, tfm, key, keylen);
	return 0;
}

/***
* Sets the authentication tag size.
* @function setauthsize
* @tparam integer tagsize tag size in bytes
* @raise on unsupported size
*/
static int luacrypto_aead_setauthsize(lua_State *L)
{
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	unsigned int tagsize = (unsigned int)lunatik_checkinteger(L, 2, 1, UINT_MAX);
	lunatik_try(L, crypto_aead_setauthsize, tfm, tagsize);
	return 0;
}

/***
* Returns the required IV size in bytes.
* @function ivsize
* @treturn integer
*/
static int luacrypto_aead_ivsize(lua_State *L)
{
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	lua_pushinteger(L, crypto_aead_ivsize(tfm));
	return 1;
}

/***
* Returns the authentication tag size in bytes.
* @function authsize
* @treturn integer
*/
static int luacrypto_aead_authsize(lua_State *L)
{
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	lua_pushinteger(L, crypto_aead_authsize(tfm));
	return 1;
}

typedef struct luacrypto_aead_request_s {
	struct scatterlist sg;
	struct aead_request *aead;
	const char *combined;
	size_t combined_len;
	u8 *iv;
	size_t iv_len;
	size_t aad_len;
	size_t crypt_len;
	size_t authsize;
} luacrypto_aead_request_t;

static inline void luacrypto_aead_newrequest(lua_State *L, luacrypto_aead_request_t *request)
{
	memset(request, 0, sizeof(luacrypto_aead_request_t));
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);

	const char *iv = luaL_checklstring(L, 2, &request->iv_len);
	luaL_argcheck(L, request->iv_len == crypto_aead_ivsize(tfm), 2, "incorrect IV length");

	request->combined = luaL_checklstring(L, 3, &request->combined_len);

	request->aad_len = (size_t)lunatik_checkinteger(L, 4, 0, request->combined_len);

	request->crypt_len = request->combined_len - request->aad_len;
	request->authsize = (size_t)crypto_aead_authsize(tfm);

	request->iv = (u8 *)lunatik_checkalloc(L, request->iv_len);
	memcpy(request->iv, iv, request->iv_len);

	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	request->aead = aead_request_alloc(tfm, gfp);
	if (request->aead == NULL) {
		lunatik_free(request->iv);
		lunatik_enomem(L);
	}
}

static inline void luacrypto_aead_setrequest(luacrypto_aead_request_t *request, char *buffer, size_t buffer_len)
{
	struct aead_request *aead = request->aead;
	struct scatterlist *sg = &request->sg;

	memcpy(buffer, request->combined, request->combined_len);

	sg_init_one(sg, buffer, buffer_len);

	aead_request_set_ad(aead, request->aad_len);
	aead_request_set_crypt(aead, sg, sg, request->crypt_len, request->iv);
	aead_request_set_callback(aead, 0, NULL, NULL);
}

#define LUACRYPTO_AEAD_CHECK_ENCRYPT(L, ix, r)
#define LUACRYPTO_AEAD_CHECK_DECRYPT(L, ix, r)	\
	luaL_argcheck(L, r.crypt_len >= r.authsize, ix, "input data (ciphertext+tag) too short for tag")

#define LUACRYPTO_AEAD_LEN_ENCRYPT(r)	(r.combined_len + r.authsize)
#define LUACRYPTO_AEAD_LEN_DECRYPT(r)	(r.combined_len)

#define LUACRYPTO_AEAD_NEWCRYPT(name, NAME, factor)					\
static int luacrypto_aead_##name(lua_State *L)						\
{											\
	luacrypto_aead_request_t request;						\
	luacrypto_aead_newrequest(L, &request);						\
											\
	LUACRYPTO_AEAD_CHECK_##NAME(L, 3, request);					\
	size_t buffer_len = LUACRYPTO_AEAD_LEN_##NAME(request);				\
											\
	char *buffer = (char *)lunatik_malloc(L, buffer_len);				\
	if (buffer == NULL) {								\
		aead_request_free(request.aead);					\
		lunatik_free(request.iv);						\
		lunatik_enomem(L);							\
	}										\
											\
	luacrypto_aead_setrequest(&request, buffer, buffer_len);			\
	int ret = crypto_aead_##name(request.aead);					\
	aead_request_free(request.aead);						\
	lunatik_free(request.iv);							\
	if (ret < 0) {									\
		lunatik_free(buffer);							\
		lunatik_throw(L, ret);							\
	}										\
	buffer_len = min(buffer_len, request.combined_len + factor * request.authsize);	\
	lunatik_pushstring(L, buffer, buffer_len);					\
	return 1;									\
}

/***
* Encrypts data with authentication. IV length must match `ivsize()`.
* Input is AAD || plaintext; output is AAD || ciphertext || tag.
* @function encrypt
* @tparam string iv initialization vector
* @tparam string combined AAD concatenated with plaintext
* @tparam integer aad_len length of the AAD prefix in `combined`
* @treturn string AAD || ciphertext || authentication tag
* @raise on encryption failure or incorrect IV length
*/
LUACRYPTO_AEAD_NEWCRYPT(encrypt, ENCRYPT, 1);

/***
* Decrypts and authenticates data. IV length must match `ivsize()`.
* Input is AAD || ciphertext || tag; output is AAD || plaintext.
* @function decrypt
* @tparam string iv initialization vector
* @tparam string combined AAD concatenated with ciphertext and tag
* @tparam integer aad_len length of the AAD prefix in `combined`
* @treturn string AAD || plaintext
* @raise on authentication failure (EBADMSG), incorrect IV length, or input too short
*/
LUACRYPTO_AEAD_NEWCRYPT(decrypt, DECRYPT, -1);

static const luaL_Reg luacrypto_aead_mt[] = {
	{"setkey", luacrypto_aead_setkey},
	{"setauthsize", luacrypto_aead_setauthsize},
	{"ivsize", luacrypto_aead_ivsize},
	{"authsize", luacrypto_aead_authsize},
	{"encrypt", luacrypto_aead_encrypt},
	{"decrypt", luacrypto_aead_decrypt},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_aead_class = {
	.name = "crypto_aead",
	.methods = luacrypto_aead_mt,
	.release = luacrypto_aead_release,
	.sleep = true,
	.shared = true,
	.pointer = true,
};

/***
* Creates a new AEAD transform object.
* @function new
* @tparam string algname algorithm name (e.g., "gcm(aes)", "ccm(aes)")
* @treturn crypto_aead
* @raise on allocation failure
* @usage
*   local aead = require("crypto.aead")
*   local cipher = aead.new("gcm(aes)")
*/
LUACRYPTO_NEW(aead, struct crypto_aead, crypto_alloc_aead, luacrypto_aead_class);

static const luaL_Reg luacrypto_aead_lib[] = {
	{"new", luacrypto_aead_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_aead, luacrypto_aead_lib, &luacrypto_aead_class, NULL);

static int __init luacrypto_aead_init(void)
{
	return 0;
}

static void __exit luacrypto_aead_exit(void)
{
}

module_init(luacrypto_aead_init);
module_exit(luacrypto_aead_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("jperon <cataclop@hotmail.com>");
MODULE_DESCRIPTION("Lunatik low-level Linux Crypto API interface (AEAD)");

