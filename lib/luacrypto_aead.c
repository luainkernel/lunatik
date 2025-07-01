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
#include <linux/crypto.h>
#include <crypto/aead.h>
#include <linux/err.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

LUNATIK_PRIVATECHECKER(luacrypto_aead_check, struct crypto_aead *);

static void luacrypto_aead_release(void *private)
{
	struct crypto_aead *tfm = (struct crypto_aead *)private;
	if (tfm)
		crypto_free_aead(tfm);
}

/***
* AEAD object methods.
* These methods are available on AEAD objects created by `crypto_aead.new()`.
* @see crypto_aead.new
* @type crypto_aead
*/

/***
* Sets the encryption key for the AEAD transform.
* @function crypto_aead:setkey
* @tparam string key The encryption key.
* @raise Error if setting the key fails (e.g., invalid key length for the algorithm).
*/
static int luacrypto_aead_setkey(lua_State *L) {
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	int ret = crypto_aead_setkey(tfm, key, keylen);
	if (ret < 0)
		luaL_error(L, "Failed to set AEAD key (err %d)", ret);
	return 0;
}

/***
* Sets the authentication tag size for the AEAD transform.
* @function crypto_aead:setauthsize
* @tparam integer tagsize The desired authentication tag size in bytes.
* @raise Error if setting the authsize fails (e.g., unsupported size).
*/
static int luacrypto_aead_setauthsize(lua_State *L) {
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	unsigned int tagsize = luaL_checkinteger(L, 2);
	int ret = crypto_aead_setauthsize(tfm, tagsize);
	if (ret < 0)
		luaL_error(L, "Failed to set AEAD authsize (err %d)", ret);
	return 0;
}

/***
* Gets the required initialization vector (IV) size for the AEAD transform.
* @function crypto_aead:ivsize
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
* @function crypto_aead:authsize
* @treturn integer The authentication tag size in bytes.
*/
static int luacrypto_aead_authsize(lua_State *L) {
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	lua_pushinteger(L, crypto_aead_authsize(tfm));
	return 1;
}

/* Auxiliary functions to calculate buffer size for luacrypto_aead_encrypt and luacrypto_aead_decrypt */

static inline size_t luacrypto_aead_get_encrypt_buf_needed(lua_State *L, size_t combined_len, unsigned int authsize_val, size_t crypt_len) {
	return combined_len + authsize_val;
}

static inline size_t luacrypto_aead_get_decrypt_buf_needed(lua_State *L, size_t combined_len, unsigned int authsize_val, size_t crypt_len) {
	luaL_argcheck(L, crypt_len >= authsize_val, 3, "input data (ciphertext+tag) too short for tag");
	return combined_len;
}

static inline int luacrypto_aead_request(lua_State *L, int (*crypt)(struct aead_request *req), size_t (*get_buf_needed)(lua_State *L, size_t combined_len, unsigned int authsize_val, size_t crypt_len), int res_factor)
{
	struct crypto_aead *tfm = luacrypto_aead_check(L, 1);
	size_t iv_len, combined_len;
	const char *iv = luaL_checklstring(L, 2, &iv_len);
	const char *combined = luaL_checklstring(L, 3, &combined_len);
	lua_Integer aad_l = luaL_checkinteger(L, 4);

	unsigned int expected_ivlen = crypto_aead_ivsize(tfm);
	luaL_argcheck(L, iv_len == expected_ivlen, 2, "incorrect IV length");
	luaL_argcheck(L, aad_l >= 0 && (size_t)aad_l <= combined_len, 4, "AAD length out of bounds");
	size_t aad_len = (size_t)aad_l;

	unsigned int authsize_val = crypto_aead_authsize(tfm);

	size_t crypt_len = combined_len - aad_len; /* plaintext_len for encrypt, ciphertext_with_tag_len for decrypt */
	size_t total_buffer_needed = get_buf_needed(L, combined_len, authsize_val, crypt_len);

	luaL_Buffer b;
	char *buf = luaL_buffinitsize(L, &b, total_buffer_needed);

	memcpy(buf, combined, combined_len);

	struct scatterlist sg_work;
	sg_init_one(&sg_work, buf, total_buffer_needed);

	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	struct aead_request *req = aead_request_alloc(tfm, gfp);
	if (!req) {
		luaL_error(L, "Failed to allocate request");
	}

	u8 *iv_data = lunatik_checkalloc(L, iv_len);
	memcpy(iv_data, iv, iv_len);

	aead_request_set_ad(req, aad_len);
	aead_request_set_crypt(req, &sg_work, &sg_work, crypt_len, iv_data);
	aead_request_set_callback(req, 0, NULL, NULL);

	int ret = crypt(req);
	if (ret < 0) {
		aead_request_free(req);
		lunatik_free(iv_data);
		luaL_error(L, "Crypto operation failed with error code %d", -ret);
	}

	luaL_pushresultsize(&b, combined_len + res_factor * (int)authsize_val);
	aead_request_free(req);
	lunatik_free(iv_data);
	return 1;
}

#define LUACRYPTO_AEAD_CRYPT_FN(name, res_factor)									\
static int luacrypto_aead_##name(lua_State *L) {									\
	return luacrypto_aead_request(L, crypto_aead_##name, luacrypto_aead_get_##name##_buf_needed, res_factor);	\
}

/***
* Encrypts data using the AEAD transform.
* The IV (nonce) must be unique for each encryption operation with the same key.
* @function crypto_aead:encrypt
* @tparam string iv The Initialization Vector (nonce). Its length must match `ivsize()`.
* @tparam string combined_data A string containing AAD (Additional Authenticated Data) concatenated with the plaintext (format: AAD || Plaintext).
* @tparam integer aad_len The length of the AAD part in `combined_data`.
* @treturn string The encrypted data, formatted as (AAD || Ciphertext || Tag).
* @raise Error on encryption failure, incorrect IV length, or allocation issues.
*/
LUACRYPTO_AEAD_CRYPT_FN(encrypt, 1);

/***
* Decrypts data using the AEAD transform.
* The IV (nonce) and AAD must match those used during encryption.
* @function crypto_aead:decrypt
* @tparam string iv The Initialization Vector (nonce). Its length must match `ivsize()`.
* @tparam string combined_data A string containing AAD (Additional Authenticated Data) concatenated with the ciphertext and tag (format: AAD || Ciphertext || Tag).
* @tparam integer aad_len The length of the AAD part in `combined_data`.
* @treturn string The decrypted data, formatted as (AAD || Plaintext).
* @raise Error on decryption failure (e.g., authentication error - EBADMSG), incorrect IV length, input data too short, or allocation issues.
*/
LUACRYPTO_AEAD_CRYPT_FN(decrypt, -1);

/*** Lua C methods for the AEAD object.
* Includes cryptographic operations and Lunatik metamethods.
* The `__close` method is important for explicit resource cleanup.
* @see crypto_aead
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
	.sleep = true,
	.pointer = true,
};

/*** Creates a new AEAD object.
* This is the constructor function for the `crypto_aead` module.
* @function crypto_aead.new
* @tparam string algname The name of the AEAD algorithm (e.g., "gcm(aes)", "ccm(aes)").
* @treturn crypto_aead The new AEAD object.
* @raise Error if the TFM object or kernel request cannot be allocated/initialized.
* @usage
*   local aead = require("crypto_aead")
*   local cipher = aead.new("gcm(aes)")
*/
static int luacrypto_aead_new(lua_State *L) {
	const char *algname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_aead_class, 0);

	struct crypto_aead *tfm = crypto_alloc_aead(algname, 0, 0);
	if (IS_ERR(tfm)) {
		long err = PTR_ERR(tfm);
		luaL_error(L, "Failed to allocate AEAD transform for %s (err %ld)", algname, err);
	}
	object->private = tfm;

	return 1;
}

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

