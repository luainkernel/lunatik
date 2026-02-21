/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/skbuff.h>

#include <lunatik.h>

#include "luaskb.h"

LUNATIK_PRIVATECHECKER(luaskb_check, struct sk_buff *);

static int luaskb_len(lua_State *L)
{
	struct sk_buff *skb = luaskb_check(L, 1);
	pr_info_ratelimited("%s:%d: skb=%p %d\n", __func__, __LINE__, skb, skb->len);

	lua_pushinteger(L, skb->len);
	return 1;
}

static int luaskb_index(lua_State *L)
{
	struct sk_buff *skb = luaskb_check(L, 1);
	const char *key = luaL_checkstring(L, 2);

	if (!strcmp(key, "len")) {
		lua_pushinteger(L, skb->len);
		return 1;
	}

	if (!strcmp(key, "hdr_len")) {
		lua_pushinteger(L, skb->hdr_len);
		return 1;
	}

	if (!strcmp(key, "truesize")) {
		lua_pushinteger(L, skb->truesize);
		return 1;
	}

	return 0;
}

static void luaskb_release(void *private)
{
	struct sk_buff *skb = (struct sk_buff*)private;
    (void)skb;
}

static const luaL_Reg luaskb_lib[] = {
	{"len", luaskb_len},
	{NULL, NULL}
};

static const luaL_Reg luaskb_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__index", luaskb_index},
	{NULL, NULL}
};

static const lunatik_class_t luaskb_class = {
	.name = "skb",
	.methods = luaskb_mt,
	.release = luaskb_release,
	.pointer = true,
	.shared = true,
};

int luaskb_reset(lunatik_object_t *object, void *ptr)
{
	lunatik_lock(object);
	if (object != NULL)
		object->private = (void*)ptr;
	lunatik_unlock(object);
	return 0;
}
EXPORT_SYMBOL(luaskb_reset);

LUNATIK_NEWLIB(skb, luaskb_lib, &luaskb_class, NULL);

lunatik_object_t *luaskb_create(struct sk_buff *skb)
{
	lunatik_object_t *object = lunatik_createobject(&luaskb_class, 0, false);

	if (object != NULL) {
		object->private = (void*)skb;
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

