/*
 * SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */

#ifndef lunatik_obj_h
#define lunatik_obj_h

#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/slab.h>
#include <linux/kref.h>

#include <lua.h>
#include <lauxlib.h>

typedef struct lunatik_class_s {
	const char *name;
	const luaL_Reg *methods;
	void (*release)(void *);
	bool sleep;
	bool shared;
	bool pointer;
} lunatik_class_t;

typedef struct lunatik_object_s {
	struct kref kref;
	const lunatik_class_t *class;
	void *private;
	union {
		struct mutex mutex;
		spinlock_t spin;
	};
	bool sleep;
	gfp_t gfp;
	bool monitor;
	bool clone;
} lunatik_object_t;

#endif /* lunatik_obj_h */