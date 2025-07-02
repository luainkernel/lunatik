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
* @module crypto_skcipher
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/crypto.h>
#include <crypto/skcipher.h>
#include <linux/err.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

LUNATIK_PRIVATECHECKER(luacrypto_skcipher_check, struct crypto_skcipher *);

static void luacrypto_skcipher_release(void *private)
{
	struct crypto_skcipher *tfm = (struct crypto_skcipher *)private;
	if (tfm)
		crypto_free_skcipher(tfm);
}

/***
* SKCIPHER Object methods.
* These methods are available on SKCIPHER TFM objects created by `crypto_skcipher.new()`.
* @type crypto_skcipher
*/

/***
* Sets the encryption key for the SKCIPHER transform.
* @function crypto_skcipher:setkey
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
* @function crypto_skcipher:ivsize
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
* @function crypto_skcipher:blocksize
* @treturn integer The block size in bytes.
*/
static int luacrypto_skcipher_blocksize(lua_State *L) {
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);
	lua_pushinteger(L, crypto_skcipher_blocksize(tfm));
	return 1;
}

static inline int luacrypto_skcipher_crypt_common(lua_State *L, int (*crypt_func)(struct skcipher_request *req)) {
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);
	size_t iv_len;
	const char *iv = luaL_checklstring(L, 2, &iv_len);
	size_t data_len;
	const char *data = luaL_checklstring(L, 3, &data_len); /* Data (plaintext or ciphertext) */
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));

	luaL_Buffer work_buffer;
	u8 *buf = luaL_buffinitsize(L, &work_buffer, data_len);
	memcpy(buf, data, data_len);

	struct scatterlist sg_work;
	sg_init_one(&sg_work, buf, data_len);

	unsigned int expected_ivlen = crypto_skcipher_ivsize(tfm);
	luaL_argcheck(L, iv_len == expected_ivlen, 2, "incorrect IV length");

	u8 *iv_data = lunatik_checkalloc(L, iv_len);
	memcpy(iv_data, iv, iv_len);

	struct skcipher_request *req = skcipher_request_alloc(tfm, gfp);
	if (!req) {
		lunatik_free(iv_data); /* Free iv_data if request allocation fails */
		luaL_error(L, "Failed to allocate request");
	}

	skcipher_request_set_crypt(req, &sg_work, &sg_work, data_len, iv_data);
	skcipher_request_set_callback(req, 0, NULL, NULL);

	int ret = crypt_func(req);
	if (ret < 0) {
		skcipher_request_free(req);
		lunatik_free(iv_data);
		luaL_error(L, "Crypto operation failed with error code %d", -ret);
	}

	luaL_pushresultsize(&work_buffer, data_len);
	skcipher_request_free(req);
	lunatik_free(iv_data);
	return 1;
}

#define LUACRYPTO_SKCIPHER_CRYPT_FN(name)					\
static int luacrypto_skcipher_##name(lua_State *L) {				\
	return luacrypto_skcipher_crypt_common(L, crypto_skcipher_##name);	\
}

/***
* Encrypts plaintext using the SKCIPHER transform.
* The IV (nonce) must be unique for each encryption operation with the same key for most modes.
* Plaintext length should be appropriate for the cipher mode (e.g., multiple of blocksize).
* @function crypto_skcipher:encrypt
* @tparam string iv The Initialization Vector. Its length must match `ivsize()`.
* @tparam string plaintext The data to encrypt.
* @treturn string The ciphertext.
* @raise Error on encryption failure, incorrect IV length, or allocation issues.
*/
LUACRYPTO_SKCIPHER_CRYPT_FN(encrypt);

/***
* Decrypts ciphertext using the SKCIPHER transform.
* The IV must match the one used during encryption.
* Ciphertext length should be appropriate for the cipher mode.
* @function crypto_skcipher:decrypt
* @tparam string iv The Initialization Vector. Its length must match `ivsize()`.
* @tparam string ciphertext The data to decrypt.
* @treturn string The plaintext.
* @raise Error on decryption failure, incorrect IV length, or allocation issues.
*/
LUACRYPTO_SKCIPHER_CRYPT_FN(decrypt);

/***
* Lua C methods for the SKCIPHER TFM object.
* Includes cryptographic operations and Lunatik metamethods.
* The `__close` method is important for explicit resource cleanup.
* @see crypto_skcipher
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
	.sleep = true,
	.pointer = true,
};

/***
* Creates a new SKCIPHER transform (TFM) object.
* This is the constructor function for the `crypto_skcipher` module.
* @function crypto_skcipher.new
* @tparam string algname The name of the skcipher algorithm (e.g., "cbc(aes)", "ctr(aes)").
* @treturn crypto_skcipher The new SKCIPHER TFM object.
* @raise Error if the TFM object or kernel request cannot be allocated/initialized.
* @usage
*   local skcipher_mod = require("crypto_skcipher")
*   local cipher = skcipher_mod.new("cbc(aes)")
*/
static int luacrypto_skcipher_new(lua_State *L) {
	const char *algname = luaL_checkstring(L, 1);
	struct crypto_skcipher *tfm;
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_skcipher_class, 0);

	tfm = crypto_alloc_skcipher(algname, 0, 0);
	if (IS_ERR(tfm)) {
		long err = PTR_ERR(tfm);
		luaL_error(L, "Failed to allocate SKCIPHER transform for %s (err %ld)", algname, err);
	}
	object->private = tfm;

	return 1;
}

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

