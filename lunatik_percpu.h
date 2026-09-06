/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_percpu_h
#define lunatik_percpu_h

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
	else /* a process instance may sleep */
		migrate_disable();
	return *this_cpu_ptr(lunatik_topercpu(object)->runtimes);
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

#define LUNATIK_ERR_PERCPU	"not allowed in a percpu runtime"

static inline void lunatik_checkpercpu(lua_State *L)
{
	if (lunatik_hascpu(L))
		luaL_error(L, LUNATIK_ERR_PERCPU);
}

#endif

