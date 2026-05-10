/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to symmetric-key ciphers (SKCIPHER).
* @classmod crypto_skcipher
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/skcipher.h>
#include <linux/err.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>

#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_skcipher_check, struct crypto_skcipher *);

LUACRYPTO_RELEASER(skcipher, struct crypto_skcipher, crypto_free_skcipher);

/***
* Sets the cipher key.
* @function setkey
* @tparam string key
* @raise on invalid key length or algorithm error
*/
static int luacrypto_skcipher_setkey(lua_State *L)
{
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_try(L, crypto_skcipher_setkey, tfm, key, keylen);
	return 0;
}

/***
* Returns the required IV size in bytes.
* @function ivsize
* @treturn integer
*/
static int luacrypto_skcipher_ivsize(lua_State *L)
{
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);
	lua_pushinteger(L, crypto_skcipher_ivsize(tfm));
	return 1;
}

/***
* Returns the cipher block size in bytes.
* @function blocksize
* @treturn integer
*/
static int luacrypto_skcipher_blocksize(lua_State *L)
{
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);
	lua_pushinteger(L, crypto_skcipher_blocksize(tfm));
	return 1;
}

typedef struct luacrypto_skcipher_request_s {
	struct scatterlist src;
	struct scatterlist dst;
	struct skcipher_request *skcipher;
	const char *data;
	size_t data_len;
	unsigned int reqsize;
	u8 *iv;
} luacrypto_skcipher_request_t;

static inline void luacrypto_skcipher_newrequest(lua_State *L, luacrypto_skcipher_request_t *request)
{
	memset(request, 0, sizeof(luacrypto_skcipher_request_t));
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);

	request->iv = luacrypto_checkiv(L, 2, crypto_skcipher_ivsize(tfm));
	request->data = luaL_checklstring(L, 3, &request->data_len);

	request->reqsize = crypto_skcipher_reqsize(tfm);
	request->skcipher = luacrypto_request_pool_acquire(L, LUACRYPTO_REQUEST_SKCIPHER,
		tfm, request->reqsize);
	if (request->skcipher == NULL) {
		lunatik_free(request->iv);
		lunatik_enomem(L);
	}
}

static inline void luacrypto_skcipher_setrequest(luacrypto_skcipher_request_t *request, char *buffer)
{
	struct skcipher_request *skcipher = request->skcipher;
	size_t data_len = request->data_len;

	sg_init_one(&request->src, request->data, data_len);	/* mapped from Lua string */
	sg_init_one(&request->dst, buffer, data_len);		/* into allocated buffer */

	skcipher_request_set_crypt(skcipher, &request->src, &request->dst, data_len, request->iv);
	skcipher_request_set_callback(skcipher, 0, NULL, NULL);
}

static int luacrypto_skcipher_crypt(lua_State *L, int (*crypt)(struct skcipher_request *))
{
	luacrypto_skcipher_request_t request;
	luacrypto_skcipher_newrequest(L, &request);

	char *buffer = (char *)lunatik_malloc(L, request.data_len + 1);
	if (buffer == NULL) {
		luacrypto_request_pool_release(L, LUACRYPTO_REQUEST_SKCIPHER, request.skcipher,
			request.reqsize);
		lunatik_free(request.iv);
		lunatik_enomem(L);
	}

	luacrypto_skcipher_setrequest(&request, buffer);
	int ret = crypt(request.skcipher);
	buffer[request.data_len] = '\0';
	luacrypto_request_pool_release(L, LUACRYPTO_REQUEST_SKCIPHER, request.skcipher,
		request.reqsize);
	lunatik_free(request.iv);
	if (ret < 0) {
		lunatik_free(buffer);
		lunatik_throw(L, ret);
	}

	lunatik_pushstring(L, buffer, request.data_len);
	return 1;
}

/***
* Encrypts data. IV length must match `ivsize()`.
* @function encrypt
* @tparam string iv initialization vector
* @tparam string data plaintext
* @treturn string ciphertext (same length as input)
* @raise on encryption failure or incorrect IV length
*/
static int luacrypto_skcipher_encrypt(lua_State *L)
{
	return luacrypto_skcipher_crypt(L, crypto_skcipher_encrypt);
}

/***
* Decrypts data. IV length must match `ivsize()`.
* @function decrypt
* @tparam string iv initialization vector
* @tparam string data ciphertext
* @treturn string plaintext (same length as input)
* @raise on decryption failure or incorrect IV length
*/
static int luacrypto_skcipher_decrypt(lua_State *L)
{
	return luacrypto_skcipher_crypt(L, crypto_skcipher_decrypt);
}

static int luacrypto_skcipher_algname(lua_State *L)
{
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);
	lua_pushstring(L, crypto_tfm_alg_name(crypto_skcipher_tfm(tfm)));
	return 1;
}

static const luaL_Reg luacrypto_skcipher_mt[] = {
	{"algname", luacrypto_skcipher_algname},
	{"setkey", luacrypto_skcipher_setkey},
	{"ivsize", luacrypto_skcipher_ivsize},
	{"blocksize", luacrypto_skcipher_blocksize},
	{"encrypt", luacrypto_skcipher_encrypt},
	{"decrypt", luacrypto_skcipher_decrypt},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_skcipher_class = {
	.name = "crypto_skcipher",
	.methods = luacrypto_skcipher_mt,
	.release = luacrypto_skcipher_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

/***
* Creates a new SKCIPHER transform object.
* @function new
* @tparam string algname algorithm name (e.g., "cbc(aes)", "ctr(aes)")
* @treturn crypto_skcipher
* @raise on allocation failure
* @usage
*   local skcipher = require("crypto").skcipher
*   local cipher = skcipher("cbc(aes)")
*/
LUACRYPTO_NEW(skcipher, struct crypto_skcipher, crypto_alloc_skcipher, luacrypto_skcipher_class);
