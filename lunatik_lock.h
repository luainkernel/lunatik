/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_lock_h
#define lunatik_lock_h

static inline void lunatik_newlock(lunatik_object_t *object)
{
	if (lunatik_isirq(object->opt))
		spin_lock_init(&object->spin);
	else
		mutex_init(&object->mutex);
}

static inline void lunatik_freelock(lunatik_object_t *object)
{
	if (!lunatik_isirq(object->opt))
		mutex_destroy(&object->mutex);
}

#define lunatik_setowner(object, task)	WRITE_ONCE((object)->owner, (task))
#define lunatik_isowner(object)		(READ_ONCE((object)->owner) == current)

/* a bottom-half unlock with IRQs off runs the pending softirqs inline, inside a kprobe handler */
#define lunatik_isirqsave(object)	(lunatik_ishardirq((object)->opt) || irqs_disabled())

static inline void lunatik_lock(lunatik_object_t *object)
{
	if (!lunatik_isirq(object->opt))
		mutex_lock(&object->mutex);
	else if (lunatik_isirqsave(object))
		spin_lock_irqsave(&object->spin, object->flags);
	else
		spin_lock_bh(&object->spin);
	lunatik_setowner(object, current);
}

static inline int lunatik_lockmutex(struct mutex *mutex)
{
	/* a killable wait does not end on a stop */
	return lunatik_iskthread() ? mutex_lock_interruptible(mutex) : mutex_lock_killable(mutex);
}

static inline int lunatik_lockkillable(lunatik_object_t *object)
{
	int ret = 0;

	if (lunatik_isirq(object->opt))
		lunatik_lock(object);
	else if ((ret = lunatik_lockmutex(&object->mutex)) == 0)
		lunatik_setowner(object, current);
	return ret;
}

static inline void lunatik_unlock(lunatik_object_t *object)
{
	lunatik_setowner(object, NULL);
	if (!lunatik_isirq(object->opt))
		mutex_unlock(&object->mutex);
	else if (lunatik_isirqsave(object))
		spin_unlock_irqrestore(&object->spin, object->flags);
	else
		spin_unlock_bh(&object->spin);
}

#endif

