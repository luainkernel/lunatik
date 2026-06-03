/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luatask_h
#define luatask_h

#include <linux/sched.h>
#include <lunatik.h>

static inline void luatask_reset(lunatik_object_t *object, struct task_struct *task)
{
	struct task_struct *ltask = (struct task_struct *)object->private;
	if (task != NULL)
		get_task_struct(task);
	if (ltask != NULL)
		put_task_struct(ltask);
	ltask = task;
}

static inline void luatask_clear(lunatik_object_t *object)
{
	luatask_reset(object, NULL);
}

static inline void luatask_close(lunatik_object_t *object)
{
	luatask_clear(object);
	lunatik_putobject(object);
}

lunatik_object_t *luatask_new(lua_State *L, struct task_struct *task);

#endif

