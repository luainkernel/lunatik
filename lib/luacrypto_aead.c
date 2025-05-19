/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

/***
Low-level Lua interface to the Linux Kernel Crypto API for AEAD
(Authenticated Encryption with Associated Data) ciphers.
 *
This module provides a `new` function to create AEAD transform objects,
which can then be used for encryption and decryption.
@see crypto_aead_tfm

@module crypto_aead
 */

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

static const lunatik_class_t luacrypto_aead_tfm_class;

typedef struct {
	struct crypto_aead *tfm;
	struct aead_request *req;

	u8 *iv_data;
	size_t iv_len;

	u8 *work_buffer;
	size_t work_buffer_len;

	size_t aad_len_in_buffer;
	size_t crypt_data_len_in_buffer; // For encrypt: PT len. For decrypt: CT+Tag len.

	struct scatterlist sg_work;
} luacrypto_aead_tfm_t;

LUNATIK_PRIVATECHECKER(luacrypto_check_aead_tfm, luacrypto_aead_tfm_t *);

static void luacrypto_aead_tfm_release(void *private)
{
	luacrypto_aead_tfm_t *tfm_ud = (luacrypto_aead_tfm_t *)private;
	if (!tfm_ud) {
		return;
	}

	kfree(tfm_ud->iv_data);
	tfm_ud->iv_data = NULL;
	kfree(tfm_ud->work_buffer);
	tfm_ud->work_buffer = NULL;

	if (tfm_ud->req) {
		aead_request_free(tfm_ud->req);
		tfm_ud->req = NULL;
	}

	if (tfm_ud->tfm && !IS_ERR(tfm_ud->tfm)) {
		crypto_free_aead(tfm_ud->tfm);
	}
}


/// AEAD Transform (TFM) methods.
// These methods are available on AEAD TFM objects created by `crypto_aead.new()`.
// @see crypto_aead.new
// @type crypto_aead_tfm

/***
Sets the encryption key for the AEAD transform.
@function crypto_aead_tfm:setkey
@tparam string key The encryption key.
@raise Error if setting the key fails (e.g., invalid key length for the algorithm).
 */
static int luacrypto_aead_tfm_setkey(lua_State *L) {
	luacrypto_aead_tfm_t *tfm_ud = luacrypto_check_aead_tfm(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	int ret = crypto_aead_setkey(tfm_ud->tfm, key, keylen);
	if (ret) return luaL_error(L, "aead_tfm:setkey: failed (%d)", ret);
	return 0;
}

/***
Sets the authentication tag size for the AEAD transform.
@function crypto_aead_tfm:setauthsize
@tparam integer tagsize The desired authentication tag size in bytes.
@raise Error if setting the authsize fails (e.g., unsupported size).
 */
static int luacrypto_aead_tfm_setauthsize(lua_State *L) {
	luacrypto_aead_tfm_t *tfm_ud = luacrypto_check_aead_tfm(L, 1);
	unsigned int tagsize = luaL_checkinteger(L, 2);
	int ret = crypto_aead_setauthsize(tfm_ud->tfm, tagsize);
	if (ret) return luaL_error(L, "failed to set authsize (%d)", ret);
	return 0;
}

/***
Gets the required initialization vector (IV) size for the AEAD transform.
@function crypto_aead_tfm:ivsize
@treturn integer The IV size in bytes.
 */
static int luacrypto_aead_tfm_ivsize(lua_State *L) {
	luacrypto_aead_tfm_t *tfm_ud = luacrypto_check_aead_tfm(L, 1);
	lua_pushinteger(L, crypto_aead_ivsize(tfm_ud->tfm));
	return 1;
}

/***
Gets the current authentication tag size for the AEAD transform.
This is the value set by `setauthsize` or the algorithm's default.
@function crypto_aead_tfm:authsize
@treturn integer The authentication tag size in bytes.
 */
static int luacrypto_aead_tfm_authsize(lua_State *L) {
	luacrypto_aead_tfm_t *tfm_ud = luacrypto_check_aead_tfm(L, 1);
	lua_pushinteger(L, crypto_aead_authsize(tfm_ud->tfm));
	return 1;
}

/***
Encrypts data using the AEAD transform.
The IV (nonce) must be unique for each encryption operation with the same key.
@function crypto_aead_tfm:encrypt
@tparam string iv The Initialization Vector (nonce). Its length must match `ivsize()`.
@tparam string combined_data A string containing AAD (Additional Authenticated Data) concatenated with the plaintext (format: AAD || Plaintext).
@tparam integer aad_len The length of the AAD part in `combined_data`.
@treturn string The encrypted data, formatted as (AAD || Ciphertext || Tag).
@raise Error on encryption failure, incorrect IV length, or allocation issues.
 */
static int luacrypto_aead_tfm_encrypt(lua_State *L) {
	luacrypto_aead_tfm_t *tfm_ud = luacrypto_check_aead_tfm(L, 1);
	size_t iv_s_len, combined_s_len, aad_s_len, actual_data_s_len;
	const char *iv_s = luaL_checklstring(L, 2, &iv_s_len);
	const char *combined_s = luaL_checklstring(L, 3, &combined_s_len); // AAD || Plaintext
	lua_Integer aad_l = luaL_checkinteger(L, 4);
	int ret;
	unsigned int authsize_val;
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int expected_ivlen;
	size_t total_buffer_needed;

	if (!tfm_ud->req) {
		return luaL_error(L, "aead_tfm:encrypt: TFM request not initialized (internal error)");
	}

	expected_ivlen = crypto_aead_ivsize(tfm_ud->tfm);
	luaL_argcheck(L, iv_s_len == expected_ivlen, 2, "incorrect IV length");
	kfree(tfm_ud->iv_data);
	tfm_ud->iv_data = kmemdup(iv_s, iv_s_len, gfp);
	if (!tfm_ud->iv_data) {
		tfm_ud->iv_len = 0;
		return luaL_error(L, "aead_tfm:encrypt: failed to allocate IV buffer");
	}
	tfm_ud->iv_len = iv_s_len;

	luaL_argcheck(L, aad_l >= 0 && (size_t)aad_l <= combined_s_len, 4, "AAD length out of bounds");
	aad_s_len = (size_t)aad_l;
	actual_data_s_len = combined_s_len - aad_s_len; // Plaintext length

	authsize_val = crypto_aead_authsize(tfm_ud->tfm);
	total_buffer_needed = aad_s_len + actual_data_s_len + authsize_val;

	if (!tfm_ud->work_buffer || tfm_ud->work_buffer_len < total_buffer_needed) {
		kfree(tfm_ud->work_buffer);
		tfm_ud->work_buffer = kmalloc(total_buffer_needed, gfp);
		if (!tfm_ud->work_buffer) {
			tfm_ud->work_buffer_len = 0;
			return luaL_error(L, "aead_tfm:encrypt: failed to allocate work buffer");
		}
		tfm_ud->work_buffer_len = total_buffer_needed;
	}

	memcpy(tfm_ud->work_buffer, combined_s, combined_s_len); // Copies AAD || Plaintext

	tfm_ud->aad_len_in_buffer = aad_s_len;
	tfm_ud->crypt_data_len_in_buffer = actual_data_s_len;

	sg_init_one(&tfm_ud->sg_work, tfm_ud->work_buffer, aad_s_len + actual_data_s_len + authsize_val);

	aead_request_set_ad(tfm_ud->req, aad_s_len);
	aead_request_set_crypt(tfm_ud->req, &tfm_ud->sg_work, &tfm_ud->sg_work, actual_data_s_len, tfm_ud->iv_data);
	aead_request_set_callback(tfm_ud->req, 0, NULL, NULL);

	ret = crypto_aead_encrypt(tfm_ud->req);
	if (ret) {
		return luaL_error(L, "aead_tfm:encrypt: encryption failed (err %d)", ret);
	}

	// After encryption, work_buffer contains: AAD || Ciphertext || Tag.
	lua_pushlstring(
		L, (const char *)(tfm_ud->work_buffer),
		tfm_ud->aad_len_in_buffer + tfm_ud->crypt_data_len_in_buffer + authsize_val
	);
	return 1;
}

/***
Decrypts data using the AEAD transform.
The IV (nonce) and AAD must match those used during encryption.
@function crypto_aead_tfm:decrypt
@tparam string iv The Initialization Vector (nonce). Its length must match `ivsize()`.
@tparam string combined_data A string containing AAD (Additional Authenticated Data) concatenated with the ciphertext and tag (format: AAD || Ciphertext || Tag).
@tparam integer aad_len The length of the AAD part in `combined_data`.
@treturn string The decrypted data, formatted as (AAD || Plaintext).
@raise Error on decryption failure (e.g., authentication error - EBADMSG), incorrect IV length, input data too short, or allocation issues.
 */
static int luacrypto_aead_tfm_decrypt(lua_State *L) {
	luacrypto_aead_tfm_t *tfm_ud = luacrypto_check_aead_tfm(L, 1);
	size_t iv_s_len, combined_s_len, aad_s_len, actual_data_s_len;
	const char *iv_s = luaL_checklstring(L, 2, &iv_s_len);
	// combined_s is AAD || CiphertextWithTag
	const char *combined_s = luaL_checklstring(L, 3, &combined_s_len);
	lua_Integer aad_l = luaL_checkinteger(L, 4);
	int ret;
	unsigned int authsize_val;
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	unsigned int expected_ivlen;
	size_t total_buffer_needed;

	if (!tfm_ud->req) {
		return luaL_error(L, "aead_tfm:decrypt: TFM request not initialized (internal error)");
	}

	expected_ivlen = crypto_aead_ivsize(tfm_ud->tfm);
	luaL_argcheck(L, iv_s_len == expected_ivlen, 2, "incorrect IV length");
	kfree(tfm_ud->iv_data);
	tfm_ud->iv_data = kmemdup(iv_s, iv_s_len, gfp);
	if (!tfm_ud->iv_data) {
		tfm_ud->iv_len = 0;
		return luaL_error(L, "aead_tfm:decrypt: failed to allocate IV buffer");
	}
	tfm_ud->iv_len = iv_s_len;

	luaL_argcheck(L, aad_l >= 0 && (size_t)aad_l <= combined_s_len, 4, "AAD length out of bounds");
	aad_s_len = (size_t)aad_l;
	actual_data_s_len = combined_s_len - aad_s_len; // CiphertextWithTag length

	authsize_val = crypto_aead_authsize(tfm_ud->tfm);
	// For decryption, work_buffer needs to hold AAD || CiphertextWithTag initially.
	// The output (AAD || Plaintext) will be shorter or same length.
	// Kernel expects source buffer to be large enough for AAD + CT + Tag.
	// Destination (which is same buffer) will receive AAD + PT.
	// So, initial combined_s_len is AAD + CT + Tag.
	total_buffer_needed = combined_s_len; // aad_s_len + actual_data_s_len

	if (!tfm_ud->work_buffer || tfm_ud->work_buffer_len < total_buffer_needed) {
		kfree(tfm_ud->work_buffer);
		tfm_ud->work_buffer = kmalloc(total_buffer_needed, gfp);
		if (!tfm_ud->work_buffer) {
			tfm_ud->work_buffer_len = 0;
			return luaL_error(L, "aead_tfm:decrypt: failed to allocate work buffer");
		}
		tfm_ud->work_buffer_len = total_buffer_needed;
	}

	memcpy(tfm_ud->work_buffer, combined_s, combined_s_len); // Copies AAD || CiphertextWithTag

	tfm_ud->aad_len_in_buffer = aad_s_len;
	tfm_ud->crypt_data_len_in_buffer = actual_data_s_len;

	// Scatterlist covers AAD and CiphertextWithTag.
	sg_init_one(&tfm_ud->sg_work, tfm_ud->work_buffer, aad_s_len + actual_data_s_len);

	aead_request_set_ad(tfm_ud->req, aad_s_len);
	aead_request_set_crypt(tfm_ud->req, &tfm_ud->sg_work, &tfm_ud->sg_work, actual_data_s_len, tfm_ud->iv_data);
	aead_request_set_callback(tfm_ud->req, 0, NULL, NULL);

	ret = crypto_aead_decrypt(tfm_ud->req);
	if (ret) {
		// Common error is -EBADMSG for authentication failure
		return luaL_error(L, "aead_tfm:decrypt: decryption failed (err %d, possibly auth error)", ret);
	}

	// After decryption, work_buffer contains: AAD || Plaintext.
	// The length of Plaintext is (ciphertext_with_tag_len - authsize_val)
	luaL_argcheck(
		L, tfm_ud->crypt_data_len_in_buffer >= authsize_val,
		3, "input data (ciphertext+tag) too short for tag"
	);
	// The length of this combined data is (aad_len_in_buffer + plaintext_len)
	lua_pushlstring(
		L, (const char *)(tfm_ud->work_buffer),
		tfm_ud->aad_len_in_buffer + (tfm_ud->crypt_data_len_in_buffer - authsize_val)
	);
	return 1;
}

/// Lua C methods for the AEAD TFM object.
// Includes cryptographic operations and Lunatik metamethods.
// The `__close` method is important for explicit resource cleanup.
// @see crypto_aead_tfm
// @see lunatik_closeobject
static const luaL_Reg luacrypto_aead_tfm_mt[] = {
	{"setkey", luacrypto_aead_tfm_setkey},
	{"setauthsize", luacrypto_aead_tfm_setauthsize},
	{"ivsize", luacrypto_aead_tfm_ivsize},
	{"authsize", luacrypto_aead_tfm_authsize},
	{"encrypt", luacrypto_aead_tfm_encrypt},
	{"decrypt", luacrypto_aead_tfm_decrypt},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

/// Lunatik class definition for AEAD TFM objects.
// This structure binds the C implementation (luacrypto_aead_tfm_t, methods, release function)
// to the Lua object system managed by Lunatik.
static const lunatik_class_t luacrypto_aead_tfm_class = {
	.name = "crypto_aead_tfm",
	.methods = luacrypto_aead_tfm_mt,
	.release = luacrypto_aead_tfm_release,
	.sleep = true,
};


/***
Creates a new AEAD transform (TFM) object.
This is the constructor function for the `crypto_aead` module.
@function crypto_aead.new
@tparam string algname The name of the AEAD algorithm (e.g., "gcm(aes)", "ccm(aes)").
@treturn crypto_aead_tfm The new AEAD TFM object.
@raise Error if the TFM object or kernel request cannot be allocated/initialized.
@usage local aead_mod = require("crypto_aead") ; local cipher = aead_mod.new("gcm(aes)")
 */
static int luacrypto_aead_new(lua_State *L) {
	const char *algname = luaL_checkstring(L, 1);
	luacrypto_aead_tfm_t *tfm_ud;
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	lunatik_object_t *object = lunatik_newobject(
		L, &luacrypto_aead_tfm_class,
		sizeof(luacrypto_aead_tfm_t)
	);
	if (!object) {
		return luaL_error(L, "crypto_aead.new: failed to create underlying AEAD TFM object");
	}
	tfm_ud = (luacrypto_aead_tfm_t *)object->private;
	memset(tfm_ud, 0, sizeof(luacrypto_aead_tfm_t));

	struct crypto_aead *tfm =  crypto_alloc_aead(algname, 0, 0);
	tfm_ud->tfm = tfm;
	if (IS_ERR(tfm_ud->tfm)) {
		long err = PTR_ERR(tfm_ud->tfm);
		return luaL_error(L, "failed to allocate AEAD transform for %s (err %ld)", algname, err);
	}

	tfm_ud->req = aead_request_alloc(tfm_ud->tfm, gfp);
	if (!tfm_ud->req) {
		// tfm_ud->tfm is guaranteed not IS_ERR here.
		crypto_free_aead(tfm_ud->tfm);
		tfm_ud->tfm = NULL;
		return luaL_error(L, "crypto_aead.new: failed to allocate kernel request for %s",
					algname);
	}
	sg_init_one(&tfm_ud->sg_work, NULL, 0);
	return 1;
}

static const luaL_Reg luacrypto_aead_lib_funcs[] = {
	{"new", luacrypto_aead_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_aead, luacrypto_aead_lib_funcs, &luacrypto_aead_tfm_class, NULL);

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
