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

typedef u8 __bitwise lunatik_opt_t;
#define LUNATIK_OPT_SOFTIRQ	((__force lunatik_opt_t)(1U << 0))
#define LUNATIK_OPT_MONITOR	((__force lunatik_opt_t)(1U << 1))
#define LUNATIK_OPT_SINGLE	((__force lunatik_opt_t)(1U << 2))
#define LUNATIK_OPT_EXTERNAL	((__force lunatik_opt_t)(1U << 3))
#define LUNATIK_OPT_NONE	((__force lunatik_opt_t)0)

typedef struct lunatik_class_s {
	const char *name;
	const luaL_Reg *methods;
	void (*release)(void *);
	lunatik_opt_t opt;
} lunatik_class_t;

typedef struct lunatik_object_s {
	struct kref kref;
	const lunatik_class_t *class;
	void *private;
	union {
		struct mutex mutex;
		spinlock_t spin;
	};
	lunatik_opt_t opt;
	gfp_t gfp;
} lunatik_object_t;

#endif /* lunatik_obj_h */
