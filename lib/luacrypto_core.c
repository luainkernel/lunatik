/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to the Linux Crypto API.
* @module crypto
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include "luacrypto.h"

static const luaL_Reg luacrypto_lib[] = {
	{"shash", luacrypto_shash_new},
	{"skcipher", luacrypto_skcipher_new},
	{"aead", luacrypto_aead_new},
	{"rng", luacrypto_rng_new},
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))
	{"comp", luacrypto_comp_new},
#endif
	{NULL, NULL}
};

static const lunatik_class_t *luacrypto_classes[] = {
	&luacrypto_shash_class,
	&luacrypto_skcipher_class,
	&luacrypto_aead_class,
	&luacrypto_rng_class,
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))
	&luacrypto_comp_class,
#endif
	NULL
};

LUNATIK_NEWLIB(crypto, luacrypto_lib, luacrypto_classes);

static int __init luacrypto_init(void)
{
	return 0;
}

static void __exit luacrypto_exit(void)
{
}

module_init(luacrypto_init);
module_exit(luacrypto_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("jperon <cataclop@hotmail.com>");
MODULE_DESCRIPTION("Lunatik Linux Crypto API interface");

