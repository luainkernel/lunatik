/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Encrypted Lua script execution using AES-256-GCM.
*
* This module provides functionality to decrypt and load or execute Lua scripts
* encrypted with AES-256 in GCM mode. Scripts are decrypted in-kernel
* and loaded immediately, with the decrypted plaintext never written
* to persistent storage.
*
* @module darken
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/aead.h>
#include <linux/scatterlist.h>

#include <lunatik.h>

#define LUADARKEN_KEYLEN	32
#define LUADARKEN_IVLEN		12
#define LUADARKEN_TAGLEN	16
#define LUADARKEN_ALG		"gcm(aes)"

typedef struct luadarken_request_s {
	struct crypto_aead *tfm;
	struct aead_request *req;
	struct scatterlist sg;
	u8 *iv;
} luadarken_request_t;

static void luadarken_freerequest(luadarken_request_t *r)
{
	kfree(r->iv);
	if (r->req)
		aead_request_free(r->req);
	if (r->tfm)
		crypto_free_aead(r->tfm);
}

static struct crypto_aead *luadarken_setkey(lua_State *L, const char *key)
{
	struct crypto_aead *tfm = crypto_alloc_aead(LUADARKEN_ALG, 0, CRYPTO_ALG_ASYNC);
	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));

	int ret = crypto_aead_setkey(tfm, key, LUADARKEN_KEYLEN);
	if (ret < 0) {
		crypto_free_aead(tfm);
		lunatik_throw(L, ret);
	}
	return tfm;
}

static char *luadarken_setrequest(lua_State *L, luadarken_request_t *r,
	const char *ct, size_t ct_len, const char *iv, const char *key)
{
	r->tfm = luadarken_setkey(L, key);

	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));

	r->req = aead_request_alloc(r->tfm, gfp);
	if (r->req == NULL)
		goto err;

	r->iv = kmemdup(iv, LUADARKEN_IVLEN, gfp);
	if (r->iv == NULL)
		goto err;

	char *buf = kmemdup(ct, ct_len, gfp | __GFP_NOWARN); /* the script sizes it, and a NULL raises */
	if (buf == NULL)
		goto err;

	sg_init_one(&r->sg, buf, ct_len);
	aead_request_set_ad(r->req, 0);
	aead_request_set_crypt(r->req, &r->sg, &r->sg, ct_len, r->iv);
	aead_request_set_callback(r->req, 0, NULL, NULL);

	return buf;
err:
	luadarken_freerequest(r);
	lunatik_enomem(L);
	return NULL; /* unreachable */
}

static void luadarken_decrypt(lua_State *L, luadarken_request_t *r, char *buf)
{
	int ret = crypto_aead_decrypt(r->req);
	luadarken_freerequest(r);

	if (ret < 0) {
		kfree_sensitive(buf);
		lunatik_throw(L, ret);
	}
}

/***
* Decrypts an encrypted Lua script and loads it without running it.
* The ciphertext carries its 16-byte tag at the end and no associated data, and nothing is loaded
* unless the tag matches. The decrypted script is Lua source or a chunk `lunatic` compiled, and the
* function it loads into has the runtime's global environment. A script that calls the function as
* it returns it, `return darken.load(...)(...)`, runs it as a tail call, at the depth of the
* script itself, where one that `darken.run` runs nests below a C call. It allocates a crypto
* transform, which may sleep: call it from a process runtime or from a script body, never from a
* softirq or hardirq callback.
* @function load
* @tparam string ciphertext encrypted Lua script followed by its 16-byte tag (binary).
* @tparam string iv 12-byte initialization vector (binary).
* @tparam string key 32-byte AES-256 key (binary).
* @treturn function the loaded script.
* @raise "IV must be 12 bytes", "key must be 32 bytes", "not allowed once the runtime is armed" from
*   an interrupt-context runtime past its body, "EBADMSG" when the tag does not match (a wrong key
*   or IV, or a ciphertext altered or shorter than the tag), the errno name of a failed transform
*   allocation, key setting or decryption, "not enough memory", or the load error of the decrypted
*   script.
*/
static int luadarken_load(lua_State *L)
{
	lunatik_checkarmed(L);

	size_t ct_len, iv_len, key_len;
	const char *ct = luaL_checklstring(L, 1, &ct_len);
	const char *iv = luaL_checklstring(L, 2, &iv_len);
	const char *key = luaL_checklstring(L, 3, &key_len);

	luaL_argcheck(L, iv_len == LUADARKEN_IVLEN, 2, "IV must be 12 bytes");
	luaL_argcheck(L, key_len == LUADARKEN_KEYLEN, 3, "key must be 32 bytes");
	if (ct_len < LUADARKEN_TAGLEN)
		lunatik_throw(L, -EBADMSG);

	luadarken_request_t r = {0};
	char *buf = luadarken_setrequest(L, &r, ct, ct_len, iv, key);
	luadarken_decrypt(L, &r, buf);

	int ret = luaL_loadbuffer(L, buf, ct_len - LUADARKEN_TAGLEN, "=darken");
	kfree_sensitive(buf);

	if (ret != LUA_OK)
		lua_error(L);
	return 1;
}

/***
* Decrypts and executes an encrypted Lua script: `darken.load` followed by a call of what it loads.
* @function run
* @tparam string ciphertext encrypted Lua script followed by its 16-byte tag (binary).
* @tparam string iv 12-byte initialization vector (binary).
* @tparam string key 32-byte AES-256 key (binary).
* @return The return values from the executed script.
* @raise what `darken.load` raises, or the error the script raises.
*/
static int luadarken_run(lua_State *L)
{
	luadarken_load(L);
	int base = lua_gettop(L);
	lua_call(L, 0, LUA_MULTRET);
	return lua_gettop(L) - base + 1;
}

static const luaL_Reg luadarken_lib[] = {
	{"load", luadarken_load},
	{"run", luadarken_run},
	{NULL, NULL}
};

LUNATIK_NEWLIB(darken, luadarken_lib, NULL);

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
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_DESCRIPTION("Lunatik darken — AES-256-GCM script decryption");

