/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luatask_h
#define luatask_h

#include <lunatik.h>

lunatik_object_t *luatask_new(lua_State *L, struct task_struct *task);
int luatask_stop(lunatik_object_t *object);
lunatik_object_t *luatask_run(lua_State *L, int (*threadfn)(void *data), void *data, const char *name);

#endif

