/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Crypto API for
* symmetric-key ciphers (SKCIPHER).
*
* This module provides a `new` function to create SKCIPHER transform objects,
* which can then be used for encryption and decryption with various block cipher
* algorithms and modes.
*
* @module crypto.skcipher
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>
#include <crypto/skcipher.h>
#include <linux/err.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_skcipher_check, struct crypto_skcipher *);

LUACRYPTO_RELEASER(skcipher, struct crypto_skcipher, crypto_free_skcipher, NULL);

/***
* SKCIPHER Object methods.
* These methods are available on SKCIPHER TFM objects created by `crypto_skcipher.new()`.
* @type SKCIPHER
*/

/***
* Sets the encryption key for the SKCIPHER transform.
* @function setkey
* @tparam string key The encryption key.
* @raise Error if setting the key fails (e.g., invalid key length for the algorithm).
*/
static int luacrypto_skcipher_setkey(lua_State *L) {
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_try(L, crypto_skcipher_setkey, tfm, key, keylen);
	return 0;
}

/***
* Gets the required initialization vector (IV) size for the SKCIPHER transform.
* @function ivsize
* @treturn integer The IV size in bytes.
*/
static int luacrypto_skcipher_ivsize(lua_State *L) {
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);
	lua_pushinteger(L, crypto_skcipher_ivsize(tfm));
	return 1;
}

/***
* Gets the block size of the SKCIPHER transform.
* Data processed by encrypt/decrypt should typically be a multiple of this size,
* depending on the cipher mode.
* @function blocksize
* @treturn integer The block size in bytes.
*/
static int luacrypto_skcipher_blocksize(lua_State *L) {
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);
	lua_pushinteger(L, crypto_skcipher_blocksize(tfm));
	return 1;
}

static inline struct skcipher_request *luacrypto_skcipher_newrequest(lua_State *L, const char **data, u8 **iv,
	size_t *data_len)
{
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);

	size_t iv_len;
	const char *l_iv = luaL_checklstring(L, 2, &iv_len);
	luaL_argcheck(L, iv_len == crypto_skcipher_ivsize(tfm), 2, "incorrect IV length");

	*data = luaL_checklstring(L, 3, data_len);

	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	struct skcipher_request *request = lunatik_checknull(L, skcipher_request_alloc(tfm, gfp));
	*iv = (u8 *)lunatik_checkalloc(L, iv_len);
	memcpy(*iv, l_iv, iv_len);

	return request;
}

static inline void luacrypto_skcipher_setrequest(lua_State *L, struct skcipher_request *request, const char *data, u8 *iv,
	size_t data_len, char *buffer)
{
	memcpy(buffer, data, data_len);

	struct scatterlist sg_work;
	sg_init_one(&sg_work, buffer, data_len);

	skcipher_request_set_crypt(request, &sg_work, &sg_work, data_len, iv);
	skcipher_request_set_callback(request, 0, NULL, NULL);
}

LUACRYPTO_FREEREQUEST(skcipher, struct skcipher_request, skcipher_request_free);

#define LUACRYPTO_SKCIPHER_NEWCRYPT(name)								\
static int luacrypto_skcipher_##name(lua_State *L) {							\
	const char *data;										\
	u8 *iv;												\
	size_t data_len;										\
	struct skcipher_request *request = luacrypto_skcipher_newrequest(L, &data, &iv, &data_len);	\
													\
	luaL_Buffer B;											\
	char *buffer = luaL_buffinitsize(L, &B, data_len);						\
	luacrypto_skcipher_setrequest(L, request, data, iv, data_len, buffer);				\
	int ret = crypto_skcipher_##name(request);							\
	luacrypto_skcipher_freerequest(request, iv);							\
	if (ret < 0)											\
		luaL_error(L, "Crypto operation failed with error code %d", -ret);			\
													\
	luaL_pushresultsize(&B, data_len);								\
	return 1;											\
}

/***
* Encrypts plaintext using the SKCIPHER transform.
* The IV (nonce) must be unique for each encryption operation with the same key for most modes.
* Plaintext length should be appropriate for the cipher mode (e.g., multiple of blocksize).
* @function encrypt
* @tparam string iv The Initialization Vector. Its length must match `ivsize()`.
* @tparam string plaintext The data to encrypt.
* @treturn string The ciphertext.
* @raise Error on encryption failure, incorrect IV length, or allocation issues.
*/
LUACRYPTO_SKCIPHER_NEWCRYPT(encrypt);

/***
* Decrypts ciphertext using the SKCIPHER transform.
* The IV must match the one used during encryption.
* Ciphertext length should be appropriate for the cipher mode.
* @function decrypt
* @tparam string iv The Initialization Vector. Its length must match `ivsize()`.
* @tparam string ciphertext The data to decrypt.
* @treturn string The plaintext.
* @raise Error on decryption failure, incorrect IV length, or allocation issues.
*/
LUACRYPTO_SKCIPHER_NEWCRYPT(decrypt);

/***
* Lua C methods for the SKCIPHER TFM object.
* Includes cryptographic operations and Lunatik metamethods.
* The `__close` method is important for explicit resource cleanup.
* @see skcipher
* @see lunatik_closeobject
*/

static const luaL_Reg luacrypto_skcipher_mt[] = {
	{"setkey", luacrypto_skcipher_setkey},
	{"ivsize", luacrypto_skcipher_ivsize},
	{"blocksize", luacrypto_skcipher_blocksize},
	{"encrypt", luacrypto_skcipher_encrypt},
	{"decrypt", luacrypto_skcipher_decrypt},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

/***
* Lunatik class definition for SKCIPHER TFM objects.
* This structure binds the C implementation (luacrypto_skcipher_t, methods, release function)
* to the Lua object system managed by Lunatik.
*/

static const lunatik_class_t luacrypto_skcipher_class = {
	.name = "crypto_skcipher",
	.methods = luacrypto_skcipher_mt,
	.release = luacrypto_skcipher_release,
	.flags = LUNATIK_CLASS_SLEEPABLE,
	.pointer = true,
};

/***
* Creates a new SKCIPHER transform (TFM) object.
* This is the constructor function for the `crypto_skcipher` module.
* @function new
* @tparam string algname The name of the skcipher algorithm (e.g., "cbc(aes)", "ctr(aes)").
* @treturn skcipher The new SKCIPHER TFM object.
* @raise Error if the TFM object or kernel request cannot be allocated/initialized.
* @usage
*   local skcipher = require("crypto.skcipher")
*   local cipher = skcipher.new("cbc(aes)")
* @within skcipher
*/
LUACRYPTO_NEW(skcipher, struct crypto_skcipher, crypto_alloc_skcipher, luacrypto_skcipher_class, NULL);

static const luaL_Reg luacrypto_skcipher_lib[] = {
	{"new", luacrypto_skcipher_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_skcipher, luacrypto_skcipher_lib, &luacrypto_skcipher_class, NULL);

static int __init luacrypto_skcipher_init(void)
{
	return 0;
}

static void __exit luacrypto_skcipher_exit(void)
{
}

module_init(luacrypto_skcipher_init);
module_exit(luacrypto_skcipher_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("jperon <cataclop@hotmail.com>");
MODULE_DESCRIPTION("Lunatik low-level Linux Crypto API interface (SKCIPHER)");

