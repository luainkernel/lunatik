/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Encrypted Lua script execution using AES-256-CTR.
*
* This module provides functionality to decrypt and execute Lua scripts
* encrypted with AES-256 in CTR mode. Scripts are decrypted in-kernel
* and executed immediately, with the decrypted plaintext never written
* to persistent storage.
*
* @module darken
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/skcipher.h>
#include <linux/scatterlist.h>

#include <lunatik.h>

#define LUADARKEN_KEYLEN	32
#define LUADARKEN_IVLEN		16
#define LUADARKEN_ALG		"ctr(aes)"

typedef struct luadarken_request_s {
	struct crypto_skcipher *tfm;
	struct skcipher_request *req;
	u8 *iv;
} luadarken_request_t;

static void luadarken_freerequest(luadarken_request_t *r)
{
	kfree(r->iv);
	if (r->req)
		skcipher_request_free(r->req);
	if (r->tfm)
		crypto_free_skcipher(r->tfm);
}

static struct crypto_skcipher *luadarken_setkey(lua_State *L, const char *key)
{
	struct crypto_skcipher *tfm = crypto_alloc_skcipher(LUADARKEN_ALG, 0, 0);
	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));

	int ret = crypto_skcipher_setkey(tfm, key, LUADARKEN_KEYLEN);
	if (ret < 0) {
		crypto_free_skcipher(tfm);
		lunatik_throw(L, ret);
	}
	return tfm;
}

static char *luadarken_setrequest(lua_State *L, luadarken_request_t *r,
	const char *ct, size_t ct_len, const char *iv, const char *key)
{
	r->tfm = luadarken_setkey(L, key);

	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));

	r->req = skcipher_request_alloc(r->tfm, gfp);
	if (r->req == NULL)
		goto err;

	r->iv = kmemdup(iv, LUADARKEN_IVLEN, gfp);
	if (r->iv == NULL)
		goto err;

	char *buf = kmemdup(ct, ct_len, gfp);
	if (buf == NULL)
		goto err;

	struct scatterlist sg;
	sg_init_one(&sg, buf, ct_len);
	skcipher_request_set_crypt(r->req, &sg, &sg, ct_len, r->iv);
	skcipher_request_set_callback(r->req, 0, NULL, NULL);

	return buf;
err:
	luadarken_freerequest(r);
	lunatik_enomem(L);
	return NULL; /* unreachable */
}

static void luadarken_decrypt(lua_State *L, luadarken_request_t *r)
{
	int ret = crypto_skcipher_decrypt(r->req);
	luadarken_freerequest(r);

	if (ret < 0)
		lunatik_throw(L, ret);
}

/***
* Decrypts and executes an encrypted Lua script.
* @function run
* @tparam string ciphertext encrypted Lua script (binary).
* @tparam string iv 16-byte initialization vector (binary).
* @tparam string key 32-byte AES-256 key (binary).
* @return The return values from the executed script.
* @raise Error if decryption fails or IV/key length is invalid.
*/
static int luadarken_run(lua_State *L)
{
	size_t ct_len, iv_len, key_len;
	const char *ct = luaL_checklstring(L, 1, &ct_len);
	const char *iv = luaL_checklstring(L, 2, &iv_len);
	const char *key = luaL_checklstring(L, 3, &key_len);

	luaL_argcheck(L, iv_len == LUADARKEN_IVLEN, 2, "IV must be 16 bytes");
	luaL_argcheck(L, key_len == LUADARKEN_KEYLEN, 3, "key must be 32 bytes");

	luadarken_request_t r = {0};
	char *buf = luadarken_setrequest(L, &r, ct, ct_len, iv, key);
	luadarken_decrypt(L, &r);

	int ret = luaL_loadbufferx(L, buf, ct_len, "=darken", "t");
	kfree(buf);

	if (ret != LUA_OK)
		lua_error(L);

	int base = lua_gettop(L);
	lua_call(L, 0, LUA_MULTRET);
	return lua_gettop(L) - base + 1;
}

static const luaL_Reg luadarken_lib[] = {
	{"run", luadarken_run},
	{NULL, NULL}
};

LUNATIK_NEWLIB(darken, luadarken_lib, NULL, NULL);

static int __init luadarken_init(void)
{
	return 0;
}

static void __exit luadarken_exit(void)
{
}

module_init(luadarken_init);
module_exit(luadarken_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_DESCRIPTION("Lunatik darken — AES-256-CTR script decryption");

