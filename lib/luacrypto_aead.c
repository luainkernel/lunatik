/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to AEAD (Authenticated Encryption with Associated Data) ciphers.
* @classmod crypto_aead
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/aead.h>
#include <linux/err.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>

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
	struct scatterlist src[2];	/* AAD + data */
	struct scatterlist dst[2];	/* AAD prefix + output */
	struct aead_request *aead;
	const char *data;
	const char *aad;
	u8 *iv;
	size_t aad_len;
	size_t crypt_len;
	size_t authsize;
	unsigned int reqsize;
} luacrypto_aead_request_t;

static inline void luacrypto_aead_newrequest(lua_State *L, luacrypto_aead_request_t *request)
{
	memset(request, 0, sizeof(luacrypto_aead_request_t));
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);

	request->iv = luacrypto_checkiv(L, 2, crypto_aead_ivsize(tfm));
	request->data = luaL_checklstring(L, 3, &request->crypt_len);
	request->aad = luaL_optlstring(L, 4, "", &request->aad_len);

	request->authsize = crypto_aead_authsize(tfm);
	request->reqsize = crypto_aead_reqsize(tfm);
	request->aead = luacrypto_request_pool_acquire(L, LUACRYPTO_REQUEST_AEAD,
		tfm, request->reqsize);
	if (request->aead == NULL) {
		lunatik_free(request->iv);
		lunatik_enomem(L);
	}
}

static inline void luacrypto_aead_setrequest(luacrypto_aead_request_t *request, char *buffer, size_t output_len)
{
	struct aead_request *aead = request->aead;
	struct scatterlist *src = request->src;
	struct scatterlist *dst = request->dst;
	unsigned int n = request->aad_len ? 2 : 1;

	/* src maps the Lua input strings directly (no copy). */
	sg_init_table(src, n);
	if (request->aad_len)
		sg_set_buf(&src[0], request->aad, request->aad_len);
	sg_set_buf(&src[n - 1], request->data, request->crypt_len);

	/* dst mirrors the AAD prefix and reserves room for the output. */
	if (request->aad_len)
		memcpy(buffer, request->aad, request->aad_len);
	sg_init_table(dst, n);
	if (request->aad_len)
		sg_set_buf(&dst[0], buffer, request->aad_len);
	sg_set_buf(&dst[n - 1], buffer + request->aad_len, output_len ? output_len : 1);

	aead_request_set_ad(aead, request->aad_len);
	aead_request_set_crypt(aead, src, dst, request->crypt_len, request->iv);
	aead_request_set_callback(aead, 0, NULL, NULL);
}

static inline char *luacrypto_aead_prepare(lua_State *L, luacrypto_aead_request_t *request, size_t output_len)
{
	size_t buffer_len = request->aad_len + (output_len ? output_len : 1);
	char *buffer = (char *)lunatik_malloc(L, buffer_len);
	if (buffer == NULL) {
		luacrypto_request_pool_release(L, LUACRYPTO_REQUEST_AEAD, request->aead,
			request->reqsize);
		lunatik_free(request->iv);
		lunatik_enomem(L);
	}
	luacrypto_aead_setrequest(request, buffer, output_len);
	return buffer;
}

static inline int luacrypto_aead_finish(lua_State *L, luacrypto_aead_request_t *request,
	char *buffer, int ret, size_t output_len)
{
	luacrypto_request_pool_release(L, LUACRYPTO_REQUEST_AEAD, request->aead,
		request->reqsize);
	lunatik_free(request->iv);
	if (ret < 0) {
		lunatik_free(buffer);
		lunatik_throw(L, ret);
	}
	lua_pushlstring(L, buffer + request->aad_len, output_len);
	lunatik_free(buffer);
	return 1;
}

/***
* Encrypts plaintext with authentication.
* IV length must match `ivsize()`.
* @function encrypt
* @tparam string iv initialization vector
* @tparam string plaintext data to encrypt
* @tparam[opt] string aad additional authenticated data (default: empty string)
* @treturn string ciphertext concatenated with authentication tag
* @raise on encryption failure or incorrect IV length
*/
static int luacrypto_aead_encrypt(lua_State *L)
{
	luacrypto_aead_request_t request;
	luacrypto_aead_newrequest(L, &request);
	size_t output_len = request.crypt_len + request.authsize;
	char *buffer = luacrypto_aead_prepare(L, &request, output_len);
	int ret = crypto_aead_encrypt(request.aead);
	return luacrypto_aead_finish(L, &request, buffer, ret, output_len);
}

/***
* Decrypts and authenticates ciphertext.
* IV length must match `ivsize()`. Raises EBADMSG on authentication failure.
* @function decrypt
* @tparam string iv initialization vector
* @tparam string ciphertext_with_tag ciphertext concatenated with authentication tag
* @tparam[opt] string aad additional authenticated data (default: empty string)
* @treturn string decrypted plaintext
* @raise on authentication failure (EBADMSG), incorrect IV length, or input too short
*/
static int luacrypto_aead_decrypt(lua_State *L)
{
	luacrypto_aead_request_t request;
	luacrypto_aead_newrequest(L, &request);
	if (request.crypt_len < request.authsize) {
		luacrypto_request_pool_release(L, LUACRYPTO_REQUEST_AEAD, request.aead,
			request.reqsize);
		lunatik_free(request.iv);
		lunatik_throw(L, -EBADMSG);
	}
	size_t output_len = request.crypt_len - request.authsize;
	char *buffer = luacrypto_aead_prepare(L, &request, output_len);
	int ret = crypto_aead_decrypt(request.aead);
	return luacrypto_aead_finish(L, &request, buffer, ret, output_len);
}

static int luacrypto_aead_algname(lua_State *L)
{
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	lua_pushstring(L, crypto_tfm_alg_name(crypto_aead_tfm(tfm)));
	return 1;
}

static const luaL_Reg luacrypto_aead_mt[] = {
	{"algname", luacrypto_aead_algname},
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

const lunatik_class_t luacrypto_aead_class = {
	.name = "crypto_aead",
	.methods = luacrypto_aead_mt,
	.release = luacrypto_aead_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

/***
* Creates a new AEAD transform object.
* @function new
* @tparam string algname algorithm name (e.g., "gcm(aes)", "ccm(aes)")
* @treturn crypto_aead
* @raise on allocation failure
* @usage
*   local aead = require("crypto").aead
*   local cipher = aead("gcm(aes)")
*/
LUACRYPTO_NEW(aead, struct crypto_aead, crypto_alloc_aead, luacrypto_aead_class);
