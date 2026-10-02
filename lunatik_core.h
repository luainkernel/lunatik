/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_core_h
#define lunatik_core_h

int lunatik_newruntime(lunatik_object_t **pruntime, lua_State *Lfrom, const char *script, lunatik_opt_t opt,
	lunatik_object_t *percpu, int cpu);
int lunatik_resume(lua_State *Lto, lua_State *Lfrom, int ixfrom, int nargs);
int lunatik_closekillable(lunatik_object_t *object);

extern const lunatik_class_t lunatik_percpu_class;
int lunatik_percpu(lua_State *L);

#ifdef MODULE
void lunatik_resolve(void);
#else
#define lunatik_resolve()
#endif

#endif

