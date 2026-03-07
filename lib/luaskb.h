/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luaskb_h
#define luaskb_h

#include <lunatik.h>
#include "luadata.h"

typedef struct {
	struct sk_buff *skb;
	lunatik_object_t *data;
} luaskb_t;

#define luaskb_reset(object, skb)	(((luaskb_t *)(object)->private)->skb = (skb))

static inline void luaskb_clear(lunatik_object_t *object)
{
	luaskb_t *lskb = (luaskb_t *)object->private;
	luadata_clear(lskb->data);
	lskb->skb = NULL;
}

lunatik_object_t *luaskb_new(lua_State *L);

#define luaskb_attach(L, obj, field)	lunatik_attach(L, obj, field, luaskb_new)

#endif

