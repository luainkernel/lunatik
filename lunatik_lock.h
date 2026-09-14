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
}

static inline void lunatik_unlock(lunatik_object_t *object)
{
	if (!lunatik_isirq(object->opt))
		mutex_unlock(&object->mutex);
	else if (lunatik_isirqsave(object))
		spin_unlock_irqrestore(&object->spin, object->flags);
	else
		spin_unlock_bh(&object->spin);
}

static inline int lunatik_trylock(lunatik_object_t *object)
{
	if (likely(!lunatik_ismonitor(object->opt)))
		return 1;
	if (!lunatik_isirq(object->opt))
		return mutex_trylock(&object->mutex);
	if (lunatik_isirqsave(object))
		return spin_trylock_irqsave(&object->spin, object->flags);
	return spin_trylock_bh(&object->spin);
}

#endif

