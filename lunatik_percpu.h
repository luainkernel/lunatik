/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_percpu_h
#define lunatik_percpu_h

#include <linux/list.h>
#include <linux/percpu.h>
#include <linux/preempt.h>

#define LUNATIK_CPU_NONE	(-1)
#define lunatik_getcpu(L)	(lunatik_extra(L)->cpu)
#define lunatik_hascpu(L)	(lunatik_getcpu(L) != LUNATIK_CPU_NONE)
#define lunatik_getpercpu(L)	(lunatik_extra(L)->percpu)

typedef struct lunatik_percpu_s {
	lunatik_object_t * __percpu *runtimes;
	lunatik_object_t **data;
	unsigned int ndata;
} lunatik_percpu_t;

#define lunatik_topercpu(object)	((lunatik_percpu_t *)(object)->private)

static inline lunatik_object_t *lunatik_pin(lunatik_object_t *object)
{
	if (likely(!lunatik_ispercpu(object->opt)))
		return object;

	if (lunatik_isirq(object->opt))
		preempt_disable();
	else /* a process runtime may sleep */
		migrate_disable();
	/* pairs with smp_store_release() in lunatik_newruntime(); NULL until this CPU's runtime is published */
	return smp_load_acquire(this_cpu_ptr(lunatik_topercpu(object)->runtimes));
}

static inline void lunatik_unpin(lunatik_object_t *object)
{
	if (likely(!lunatik_ispercpu(object->opt)))
		return;

	if (lunatik_isirq(object->opt))
		preempt_enable();
	else
		migrate_enable();
}

extern const lunatik_class_t lunatik_percpu_class;

int lunatik_percpu(lua_State *L);
lunatik_object_t *lunatik_percpudata(lua_State *L, const lunatik_class_t *class, size_t size);

/* the head a registration shared by the runtimes of a percpu set begins with */
typedef struct lunatik_shared_s {
	struct hlist_node node;
	lunatik_object_t *runtime;
} lunatik_shared_t;

typedef bool (*lunatik_match_t)(const lunatik_shared_t *shared, const lunatik_shared_t *spec);
typedef void (*lunatik_arm_t)(lua_State *L, lunatik_shared_t *shared);

typedef struct lunatik_sharing_s {
	const lunatik_class_t *class;	/* percpu data holding the list of registrations */
	size_t size;			/* of the registration, which begins with lunatik_shared_t */
	lunatik_match_t match;
	lunatik_arm_t arm;		/* registers with the kernel; frees what it took before raising */
	const char *registered;		/* raised when this runtime already registered the same target */
} lunatik_sharing_t;

lunatik_shared_t *lunatik_share(lua_State *L, lunatik_object_t *percpu, const lunatik_sharing_t *sharing,
	const lunatik_shared_t *spec);
lunatik_shared_t *lunatik_own(lua_State *L, lunatik_object_t *runtime, const lunatik_sharing_t *sharing,
	const lunatik_shared_t *spec);

#define LUNATIK_PERCPUDATA(prefix, cname, T, free)					\
static void prefix##_release(void *private)					\
{										\
	lunatik_shared_t *shared;						\
	struct hlist_node *next;						\
										\
	hlist_for_each_entry_safe(shared, next, (struct hlist_head *)private, node) {	\
		hlist_del(&shared->node);					\
		free((T *)shared);						\
	}									\
}										\
static const lunatik_class_t prefix##_class = {					\
	.name = cname,								\
	.release = prefix##_release,						\
}

#define LUNATIK_ERR_PERCPU	"not allowed in a percpu runtime"

static inline void lunatik_checkpercpu(lua_State *L)
{
	if (lunatik_hascpu(L))
		luaL_error(L, LUNATIK_ERR_PERCPU);
}

#endif

