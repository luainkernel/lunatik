/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luaskb_h
#define luaskb_h

#include <lunatik.h>
#include "luadata.h"

enum {
	LUASKB_NET,
	LUASKB_MAC,
	LUASKB_DATA,
	LUASKB_VIEWS
};

typedef struct {
	struct sk_buff *skb;
	lunatik_object_t *view[LUASKB_VIEWS];
	bool kfunc;
} luaskb_t;

#define luaskb_foreachlayer(layer)	for (int layer = 0; (layer) < LUASKB_VIEWS; (layer)++)

#define luaskb_foreachview(lskb, layer, object)	\
	luaskb_foreachlayer(layer)			\
		if (((object) = (lskb)->view[layer]) != NULL)

#define luaskb_reset(object, skb)	(((luaskb_t *)(object)->private)->skb = (skb))

static inline void luaskb_clear(lunatik_object_t *object)
{
	luaskb_t *lskb = (luaskb_t *)object->private;
	lunatik_object_t *view;
	luaskb_foreachview(lskb, layer, view)
		luadata_clear(view);
	lskb->skb = NULL;
}

static inline void luaskb_close(lunatik_object_t *object)
{
	luaskb_clear(object);
	lunatik_putobject(object);
}

lunatik_object_t *luaskb_attach(lua_State *L, bool kfunc);

#endif

