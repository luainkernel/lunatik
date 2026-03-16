/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to symmetric-key ciphers (SKCIPHER).
* @module crypto.skcipher
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/skcipher.h>
#include <linux/err.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>

#include <lunatik.h>

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
	struct scatterlist sg;
	struct skcipher_request *skcipher;
	const char *data;
	size_t data_len;
	u8 *iv;
	size_t iv_len;
} luacrypto_skcipher_request_t;

static inline void luacrypto_skcipher_newrequest(lua_State *L, luacrypto_skcipher_request_t *request)
{
	memset(request, 0, sizeof(luacrypto_skcipher_request_t));
	struct crypto_skcipher *tfm = luacrypto_skcipher_check(L, 1);

	const char *iv = luaL_checklstring(L, 2, &request->iv_len);
	luaL_argcheck(L, request->iv_len == crypto_skcipher_ivsize(tfm), 2, "incorrect IV length");

	request->data = luaL_checklstring(L, 3, &request->data_len);

	request->iv = (u8 *)lunatik_checkalloc(L, request->iv_len);
	memcpy(request->iv, iv, request->iv_len);

	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	request->skcipher = skcipher_request_alloc(tfm, gfp);
	if (request->skcipher == NULL) {
		lunatik_free(request->iv);
		lunatik_enomem(L);
	}
}

static inline void luacrypto_skcipher_setrequest(luacrypto_skcipher_request_t *request, char *buffer)
{
	struct skcipher_request *skcipher = request->skcipher;
	struct scatterlist *sg = &request->sg;
	size_t data_len = request->data_len;

	memcpy(buffer, request->data, data_len);

	sg_init_one(sg, buffer, data_len);

	skcipher_request_set_crypt(skcipher, sg, sg, data_len, request->iv);
	skcipher_request_set_callback(skcipher, 0, NULL, NULL);
}

#define LUACRYPTO_SKCIPHER_NEWCRYPT(name)				\
static int luacrypto_skcipher_##name(lua_State *L)			\
{									\
	luacrypto_skcipher_request_t request;				\
	luacrypto_skcipher_newrequest(L, &request);			\
									\
	char *buffer = (char *)lunatik_malloc(L, request.data_len);	\
	if (buffer == NULL) {						\
		skcipher_request_free(request.skcipher);		\
		lunatik_free(request.iv);				\
		lunatik_enomem(L);					\
	}								\
									\
	luacrypto_skcipher_setrequest(&request, buffer);		\
	int ret = crypto_skcipher_##name(request.skcipher);		\
	skcipher_request_free(request.skcipher);			\
	lunatik_free(request.iv);					\
	if (ret < 0) {							\
		lunatik_free(buffer);					\
		lunatik_throw(L, ret);					\
	}								\
									\
	lunatik_pushstring(L, buffer, request.data_len);		\
	return 1;							\
}

/***
* Encrypts data. IV length must match `ivsize()`.
* @function encrypt
* @tparam string iv initialization vector
* @tparam string data plaintext
* @treturn string ciphertext (same length as input)
* @raise on encryption failure or incorrect IV length
*/
LUACRYPTO_SKCIPHER_NEWCRYPT(encrypt);

/***
* Decrypts data. IV length must match `ivsize()`.
* @function decrypt
* @tparam string iv initialization vector
* @tparam string data ciphertext
* @treturn string plaintext (same length as input)
* @raise on decryption failure or incorrect IV length
*/
LUACRYPTO_SKCIPHER_NEWCRYPT(decrypt);

static const luaL_Reg luacrypto_skcipher_mt[] = {
	{"setkey", luacrypto_skcipher_setkey},
	{"ivsize", luacrypto_skcipher_ivsize},
	{"blocksize", luacrypto_skcipher_blocksize},
	{"encrypt", luacrypto_skcipher_encrypt},
	{"decrypt", luacrypto_skcipher_decrypt},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_skcipher_class = {
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
*   local skcipher = require("crypto.skcipher")
*   local cipher = skcipher.new("cbc(aes)")
*/
LUACRYPTO_NEW(skcipher, struct crypto_skcipher, crypto_alloc_skcipher, luacrypto_skcipher_class);

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

