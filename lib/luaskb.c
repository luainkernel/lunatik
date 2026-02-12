/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/skbuff.h>

#include <lunatik.h>

#include "luaskb.h"

typedef struct luaskb_s {
	struct sk_buff *skb;
} luaskb_t;

LUNATIK_PRIVATECHECKER(luaskb_check, luaskb_t *);

static int luaskb_len(lua_State *L)
{
	luaskb_t *luaskb = luaskb_check(L, 1);
	struct sk_buff *skb = luaskb->skb;

	lua_pushinteger(L, skb->len);
	return 1;
}

static void luaskb_release(void *private)
{
	luaskb_t *luaskb = (luaskb_t *)private;
    (void)luaskb;
}

static const luaL_Reg luaskb_lib[] = {
	{"len", luaskb_len},
	{NULL, NULL}
};

static const luaL_Reg luaskb_mt[] = {
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
};

static const lunatik_class_t luaskb_class = {
	.name = "skb",
	.methods = luaskb_mt,
	.release = luaskb_release,
	.pointer = true,
};

LUNATIK_NEWLIB(skb, luaskb_lib, &luaskb_class, NULL);

lunatik_object_t *luaskb_create(struct sk_buff *skb)
{
	lunatik_object_t *object = lunatik_createobject(&luaskb_class, 0, false);

	if (object != NULL) {
		struct sk_buff *skbuff = (struct sk_buff *)object->private;
		skbuff = skb;
	}
	return object;
}
EXPORT_SYMBOL(luaskb_create);

static int __init luaskb_init(void)
{
	return 0;
}

static void __exit luaskb_exit(void)
{
}

module_init(luaskb_init);
module_exit(luaskb_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Carlos Carvalho <carloslack@gmail.com>");
MODULE_DESCRIPTION("Lunatik interface to skb abstractions.");

