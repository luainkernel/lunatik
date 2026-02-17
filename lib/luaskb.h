/*
* SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luaskb_h
#define luaskb_h

lunatik_object_t *luaskb_create(struct sk_buff *skb);
int luaskb_reset(lunatik_object_t *object, void *ptr);

#endif

