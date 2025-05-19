/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
Low-level Lua interface to the Linux Kernel Crypto API for synchronous
block ciphers (SKCIPHER - Synchronous Kernel Cipher).
 *
This module provides a `new` function to create SKCIPHER transform objects,
which can then be used for encryption and decryption with various block cipher
algorithms and modes.
@see crypto_skcipher_tfm

@module crypto_skcipher
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

static const lunatik_class_t luacrypto_skcipher_tfm_class;

typedef struct {
	struct crypto_skcipher *tfm;
	struct skcipher_request *req;

	u8 *iv_data;
	size_t iv_len;

	u8 *work_buffer;
	size_t work_buffer_len;

	struct scatterlist sg_work;
} luacrypto_skcipher_tfm_t;

LUNATIK_PRIVATECHECKER(luacrypto_check_skcipher_tfm, luacrypto_skcipher_tfm_t *);

static void luacrypto_skcipher_tfm_release(void *private)
{
	luacrypto_skcipher_tfm_t *tfm_ud = (luacrypto_skcipher_tfm_t *)private;
	if (!tfm_ud) {
		return;
	}

	kfree(tfm_ud->iv_data);
	tfm_ud->iv_data = NULL;
	kfree(tfm_ud->work_buffer);
	tfm_ud->work_buffer = NULL;

	if (tfm_ud->req) {
		skcipher_request_free(tfm_ud->req);
		tfm_ud->req = NULL;
	}

	if (tfm_ud->tfm && !IS_ERR(tfm_ud->tfm)) {
		crypto_free_skcipher(tfm_ud->tfm);
	}
}


// These methods are available on SKCIPHER TFM objects created by `crypto_skcipher.new()`.
// @see crypto_skcipher.new
// @type crypto_skcipher_tfm

/***
Sets the encryption key for the SKCIPHER transform.
@function crypto_skcipher_tfm:setkey
@tparam string key The encryption key.
@raise Error if setting the key fails (e.g., invalid key length for the algorithm).
 */
static int luacrypto_skcipher_tfm_setkey(lua_State *L) {
	luacrypto_skcipher_tfm_t *tfm_ud = luacrypto_check_skcipher_tfm(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	int ret = crypto_skcipher_setkey(tfm_ud->tfm, key, keylen);
	if (ret) return luaL_error(L, "skcipher_tfm:setkey: failed (%d)", ret);
	return 0;
}

/***
Gets the required initialization vector (IV) size for the SKCIPHER transform.
@function crypto_skcipher_tfm:ivsize
@treturn integer The IV size in bytes.
 */
static int luacrypto_skcipher_tfm_ivsize(lua_State *L) {
	luacrypto_skcipher_tfm_t *tfm_ud = luacrypto_check_skcipher_tfm(L, 1);
	lua_pushinteger(L, crypto_skcipher_ivsize(tfm_ud->tfm));
	return 1;
}

/***
Gets the block size of the SKCIPHER transform.
Data processed by encrypt/decrypt should typically be a multiple of this size,
depending on the cipher mode.
@function crypto_skcipher_tfm:blocksize
@treturn integer The block size in bytes.
 */
static int luacrypto_skcipher_tfm_blocksize(lua_State *L) {
	luacrypto_skcipher_tfm_t *tfm_ud = luacrypto_check_skcipher_tfm(L, 1);
	lua_pushinteger(L, crypto_skcipher_blocksize(tfm_ud->tfm));
	return 1;
}

static int luacrypto_skcipher_crypt_common(lua_State *L, bool encrypt) {
	luacrypto_skcipher_tfm_t *tfm_ud = luacrypto_check_skcipher_tfm(L, 1);
	size_t iv_s_len, data_s_len;
	const char *iv_s = luaL_checklstring(L, 2, &iv_s_len);
	const char *data_s = luaL_checklstring(L, 3, &data_s_len); // Data (plaintext or ciphertext)
	int ret;
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int expected_ivlen;

	if (!tfm_ud->req) {
		return luaL_error(L, "skcipher_tfm:%s: TFM request not initialized (internal error)",
				  encrypt ? "encrypt" : "decrypt");
	}

	expected_ivlen = crypto_skcipher_ivsize(tfm_ud->tfm);
	luaL_argcheck(L, iv_s_len == expected_ivlen, 2, "incorrect IV length");
	if (!tfm_ud->iv_data || tfm_ud->iv_len < iv_s_len) {
		kfree(tfm_ud->iv_data);
		tfm_ud->iv_data = kmalloc(iv_s_len, gfp);
		if (!tfm_ud->iv_data) {
			tfm_ud->iv_len = 0;
			return luaL_error(L, "skcipher_tfm:%s: failed to allocate IV buffer",
					  encrypt ? "encrypt" : "decrypt");
		}
		tfm_ud->iv_len = iv_s_len;
	}
	memcpy(tfm_ud->iv_data, iv_s, iv_s_len);

	// Data length must be appropriate for the cipher mode (e.g. multiple of blocksize for CBC)
	// The kernel will return -EINVAL if not.
	if (!tfm_ud->work_buffer || tfm_ud->work_buffer_len < data_s_len) {
		kfree(tfm_ud->work_buffer);
		tfm_ud->work_buffer = kmalloc(data_s_len, gfp);
		if (!tfm_ud->work_buffer) {
			tfm_ud->work_buffer_len = 0;
			return luaL_error(L, "skcipher_tfm:%s: failed to allocate work buffer",
					  encrypt ? "encrypt" : "decrypt");
		}
		tfm_ud->work_buffer_len = data_s_len;
	}
	memcpy(tfm_ud->work_buffer, data_s, data_s_len);

	sg_init_one(&tfm_ud->sg_work, tfm_ud->work_buffer, data_s_len);

	skcipher_request_set_crypt(tfm_ud->req, &tfm_ud->sg_work, &tfm_ud->sg_work,
				   data_s_len, tfm_ud->iv_data);
	skcipher_request_set_callback(tfm_ud->req, 0, NULL, NULL);

	if (encrypt) {
		ret = crypto_skcipher_encrypt(tfm_ud->req);
	} else {
		ret = crypto_skcipher_decrypt(tfm_ud->req);
	}

	if (ret) {
		return luaL_error(L, "skcipher_tfm:%s: operation failed (err %d)",
				  encrypt ? "encrypt" : "decrypt", ret);
	}

	lua_pushlstring(L, (const char *)tfm_ud->work_buffer, data_s_len);
	return 1;
}

/***
Encrypts plaintext using the SKCIPHER transform.
The IV (nonce) must be unique for each encryption operation with the same key for most modes.
Plaintext length should be appropriate for the cipher mode (e.g., multiple of blocksize).
@function crypto_skcipher_tfm:encrypt
@tparam string iv The Initialization Vector. Its length must match `ivsize()`.
@tparam string plaintext The data to encrypt.
@treturn string The ciphertext.
@raise Error on encryption failure, incorrect IV length, or allocation issues.
 */
static int luacrypto_skcipher_tfm_encrypt(lua_State *L) {
	return luacrypto_skcipher_crypt_common(L, true);
}

/***
Decrypts ciphertext using the SKCIPHER transform.
The IV must match the one used during encryption.
Ciphertext length should be appropriate for the cipher mode.
@function crypto_skcipher_tfm:decrypt
@tparam string iv The Initialization Vector. Its length must match `ivsize()`.
@tparam string ciphertext The data to decrypt.
@treturn string The plaintext.
@raise Error on decryption failure, incorrect IV length, or allocation issues.
 */
static int luacrypto_skcipher_tfm_decrypt(lua_State *L) {
	return luacrypto_skcipher_crypt_common(L, false);
}

static const luaL_Reg luacrypto_skcipher_tfm_mt[] = {
	{"setkey", luacrypto_skcipher_tfm_setkey},
	{"ivsize", luacrypto_skcipher_tfm_ivsize},
	{"blocksize", luacrypto_skcipher_tfm_blocksize},
	{"encrypt", luacrypto_skcipher_tfm_encrypt},
	{"decrypt", luacrypto_skcipher_tfm_decrypt},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_skcipher_tfm_class = {
	.name = "crypto_skcipher_tfm",
	.methods = luacrypto_skcipher_tfm_mt,
	.release = luacrypto_skcipher_tfm_release,
	.sleep = true,
};


/***
Creates a new SKCIPHER transform (TFM) object.
This is the constructor function for the `crypto_skcipher` module.
@function crypto_skcipher.new
@tparam string algname The name of the skcipher algorithm (e.g., "cbc(aes)", "ctr(aes)").
@treturn crypto_skcipher_tfm The new SKCIPHER TFM object.
@raise Error if the TFM object or kernel request cannot be allocated/initialized.
@usage local skcipher_mod = require("crypto_skcipher")
local cipher = skcipher_mod.new("cbc(aes)")
 */
static int luacrypto_skcipher_new(lua_State *L) {
	const char *algname = luaL_checkstring(L, 1);
	luacrypto_skcipher_tfm_t *tfm_ud;
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	lunatik_object_t *object = lunatik_newobject(
		L, &luacrypto_skcipher_tfm_class,
		sizeof(luacrypto_skcipher_tfm_t)
	);
	if (!object) {
		return luaL_error(L, "crypto_skcipher.new: failed to create underlying SKCIPHER TFM object");
	}
	tfm_ud = (luacrypto_skcipher_tfm_t *)object->private;
	memset(tfm_ud, 0, sizeof(luacrypto_skcipher_tfm_t));

	tfm_ud->tfm = crypto_alloc_skcipher(algname, 0, 0);
	if (IS_ERR(tfm_ud->tfm)) {
		long err = PTR_ERR(tfm_ud->tfm);
		tfm_ud->tfm = NULL;
		return luaL_error(L, "failed to allocate SKCIPHER transform for %s (err %ld)", algname, err);
	}

	tfm_ud->req = skcipher_request_alloc(tfm_ud->tfm, gfp);
	if (!tfm_ud->req) {
		// tfm_ud->tfm is guaranteed not IS_ERR here.
		crypto_free_skcipher(tfm_ud->tfm);
		tfm_ud->tfm = NULL;
		return luaL_error(L, "crypto_skcipher.new: failed to allocate kernel request for %s",
					algname);
	}
	sg_init_one(&tfm_ud->sg_work, NULL, 0);
	return 1;
}

static const luaL_Reg luacrypto_skcipher_lib_funcs[] = {
	{"new", luacrypto_skcipher_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_skcipher, luacrypto_skcipher_lib_funcs, &luacrypto_skcipher_tfm_class, NULL);

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