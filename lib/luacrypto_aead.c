/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Crypto API for AEAD
* (Authenticated Encryption with Associated Data) ciphers.
*
* This module provides a `new` function to create AEAD transform objects,
* which can then be used for encryption and decryption.
*
* @module crypto_aead
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>
#include <crypto/aead.h>
#include <linux/err.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_aead_check, struct crypto_aead *);

LUACRYPTO_RELEASER(aead, struct crypto_aead, crypto_free_aead, NULL);

/***
* AEAD object methods.
* These methods are available on AEAD objects created by `crypto.aead.new()`.
* @see new
* @type AEAD
*/

/***
* Sets the encryption key for the AEAD transform.
* @function setkey
* @tparam string key The encryption key.
* @raise Error if setting the key fails (e.g., invalid key length for the algorithm).
*/
static int luacrypto_aead_setkey(lua_State *L) {
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_try(L, crypto_aead_setkey, tfm, key, keylen);
	return 0;
}

/***
* Sets the authentication tag size for the AEAD transform.
* @function setauthsize
* @tparam integer tagsize The desired authentication tag size in bytes.
* @raise Error if setting the authsize fails (e.g., unsupported size).
*/
static int luacrypto_aead_setauthsize(lua_State *L) {
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	unsigned int tagsize = lunatik_checkuint(L, 2);
	lunatik_try(L, crypto_aead_setauthsize, tfm, tagsize);
	return 0;
}

/***
* Gets the required initialization vector (IV) size for the AEAD transform.
* @function ivsize
* @treturn integer The IV size in bytes.
*/
static int luacrypto_aead_ivsize(lua_State *L) {
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	lua_pushinteger(L, crypto_aead_ivsize(tfm));
	return 1;
}

/***
* Gets the current authentication tag size for the AEAD transform.
* This is the value set by `setauthsize` or the algorithm's default.
* @function authsize
* @treturn integer The authentication tag size in bytes.
*/
static int luacrypto_aead_authsize(lua_State *L) {
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	lua_pushinteger(L, crypto_aead_authsize(tfm));
	return 1;
}

static inline struct aead_request *luacrypto_aead_newrequest(lua_State *L, const char **combined, u8 **iv,
	size_t *combined_len, size_t *aad_len, size_t *crypt_len, unsigned int *authsize)
{
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);

	size_t iv_len;
	const char *l_iv = luaL_checklstring(L, 2, &iv_len);
	luaL_argcheck(L, iv_len == crypto_aead_ivsize(tfm), 2, "incorrect IV length");

	*combined = luaL_checklstring(L, 3, combined_len);

	*aad_len = (size_t)luaL_checkinteger(L, 4);
	lunatik_checkbounds(L, 4, *aad_len, 0, *combined_len);

	*crypt_len = *combined_len - *aad_len;

	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	struct aead_request *request = lunatik_checknull(L, aead_request_alloc(tfm, gfp));
	*iv = (u8 *)lunatik_checkalloc(L, iv_len);
	memcpy(*iv, l_iv, iv_len);
	*authsize = crypto_aead_authsize(tfm);

	return request;
}

static inline void luacrypto_aead_setrequest(lua_State *L, struct aead_request *request, const char *combined, u8 *iv,
	size_t combined_len, size_t aad_len, size_t crypt_len, char *buffer, size_t buffer_len)
{
	memcpy(buffer, combined, combined_len);

	struct scatterlist sg_work;
	sg_init_one(&sg_work, buffer, buffer_len);

	aead_request_set_ad(request, aad_len);
	aead_request_set_crypt(request, &sg_work, &sg_work, crypt_len, iv);
	aead_request_set_callback(request, 0, NULL, NULL);
}

LUACRYPTO_FREEREQUEST(aead, struct aead_request, aead_request_free);

#define LUACRYPTO_AEAD_CHECK_ENCRYPT(L, ix, crypt_len, authsize)
#define LUACRYPTO_AEAD_CHECK_DECRYPT(L, ix, crypt_len, authsize)	\
	luaL_argcheck(L, crypt_len >= authsize, ix, "input data (ciphertext+tag) too short for tag")

#define LUACRYPTO_AEAD_LEN_ENCRYPT(combined_len, authsize)	(combined_len + authsize)
#define LUACRYPTO_AEAD_LEN_DECRYPT(combined_len, authsize)	(combined_len)

#define LUACRYPTO_AEAD_NEWCRYPT(name, NAME, res_factor)									\
static int luacrypto_aead_##name(lua_State *L) {									\
	const char *combined;												\
	u8 *iv;														\
	unsigned int authsize;												\
	size_t combined_len, aad_len, crypt_len;									\
	struct aead_request *request = luacrypto_aead_newrequest(L, &combined, &iv, &combined_len,			\
		&aad_len, &crypt_len, &authsize); 									\
															\
	LUACRYPTO_AEAD_CHECK_##NAME(L, 3, crypt_len, authsize);								\
	size_t buffer_len = LUACRYPTO_AEAD_LEN_##NAME(combined_len, authsize);						\
															\
	luaL_Buffer B;													\
	char *buffer = luaL_buffinitsize(L, &B, buffer_len);								\
	luacrypto_aead_setrequest(L, request, combined, iv, combined_len, aad_len, crypt_len, buffer, buffer_len);	\
	int ret = crypto_aead_##name(request);										\
	luacrypto_aead_freerequest(request, iv);									\
	if (ret < 0)													\
		luaL_error(L, "crypto operation failed with error code %d", -ret);					\
															\
	luaL_pushresultsize(&B, combined_len + res_factor * (int)authsize);						\
	return 1;													\
}

/***
* Encrypts data using the AEAD transform.
* The IV (nonce) must be unique for each encryption operation with the same key.
* @function encrypt
* @tparam string iv The Initialization Vector (nonce). Its length must match `ivsize()`.
* @tparam string combined_data A string containing AAD (Additional Authenticated Data) concatenated with the plaintext (format: AAD || Plaintext).
* @tparam integer aad_len The length of the AAD part in `combined_data`.
* @treturn string The encrypted data, formatted as (AAD || Ciphertext || Tag).
* @raise Error on encryption failure, incorrect IV length, or allocation issues.
*/
LUACRYPTO_AEAD_NEWCRYPT(encrypt, ENCRYPT, 1);

/***
* Decrypts data using the AEAD transform.
* The IV (nonce) and AAD must match those used during encryption.
* @function decrypt
* @tparam string iv The Initialization Vector (nonce). Its length must match `ivsize()`.
* @tparam string combined_data A string containing AAD (Additional Authenticated Data) concatenated with the ciphertext and tag (format: AAD || Ciphertext || Tag).
* @tparam integer aad_len The length of the AAD part in `combined_data`.
* @treturn string The decrypted data, formatted as (AAD || Plaintext).
* @raise Error on decryption failure (e.g., authentication error - EBADMSG), incorrect IV length, input data too short, or allocation issues.
*/
LUACRYPTO_AEAD_NEWCRYPT(decrypt, DECRYPT, -1);

/*** Lua C methods for the AEAD object.
* Includes cryptographic operations and Lunatik metamethods.
* The `__close` method is important for explicit resource cleanup.
* @see aead
* @see lunatik_closeobject
*/
static const luaL_Reg luacrypto_aead_mt[] = {
	{"setkey", luacrypto_aead_setkey},
	{"setauthsize", luacrypto_aead_setauthsize},
	{"ivsize", luacrypto_aead_ivsize},
	{"authsize", luacrypto_aead_authsize},
	{"encrypt", luacrypto_aead_encrypt},
	{"decrypt", luacrypto_aead_decrypt},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

/*** Lunatik class definition for AEAD TFM objects.
* This structure binds the C implementation (luacrypto_aead_tfm_t, methods, release function)
* to the Lua object system managed by Lunatik.
*/
static const lunatik_class_t luacrypto_aead_class = {
	.name = "crypto_aead",
	.methods = luacrypto_aead_mt,
	.release = luacrypto_aead_release,
	.flags = LUNATIK_CLASS_SLEEPABLE,
	.pointer = true,
};

/*** Creates a new AEAD object.
* This is the constructor function for the `aead` module.
* @function .new
* @tparam string algname The name of the AEAD algorithm (e.g., "gcm(aes)", "ccm(aes)").
* @treturn aead The new AEAD object.
* @raise Error if the TFM object or kernel request cannot be allocated/initialized.
* @usage
*   local AEAD = require("crypto.aead")
*   local cipher = aead.new("gcm(aes)")
* @within aead
*/
LUACRYPTO_NEW(aead, struct crypto_aead, crypto_alloc_aead, luacrypto_aead_class, NULL);

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

