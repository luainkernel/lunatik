/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/irq_work.h>
#include <linux/llist.h>
#include <linux/percpu.h>
#include <linux/workqueue.h>

#include <lunatik.h>
#include "lunatik_defer.h"

struct workqueue_struct *lunatik_wq;

typedef struct lunatik_deferlist_s {
	struct llist_head items;
	struct irq_work irq;
} lunatik_deferlist_t;

static void lunatik_deferirq(struct irq_work *irq);

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 16, 0))
static DEFINE_PER_CPU(lunatik_deferlist_t, lunatik_deferlist) = {.irq = IRQ_WORK_INIT(lunatik_deferirq)};
#define lunatik_initdeferlist()
#else
static DEFINE_PER_CPU(lunatik_deferlist_t, lunatik_deferlist);
/* the loader does not relocate a module's per-CPU initializer */
#define lunatik_initdeferlist()	lunatik_foreachdeferirq(init_irq_work, lunatik_deferirq)
#endif

static void lunatik_finalize(struct work_struct *work)
{
	int cpu;

	for_each_possible_cpu(cpu) {
		struct llist_node *items = llist_del_all(&per_cpu_ptr(&lunatik_deferlist, cpu)->items);
		lunatik_defer_t *defer, *next;

		llist_for_each_entry_safe(defer, next, items, node)
			defer->finalize(defer);
	}
}

static DECLARE_WORK(lunatik_deferwork, lunatik_finalize);

static void lunatik_deferirq(struct irq_work *irq)
{
	queue_work(lunatik_wq, &lunatik_deferwork);
}

void lunatik_defer(lunatik_defer_t *defer, lunatik_finalize_t finalize)
{
	lunatik_deferlist_t *list = this_cpu_ptr(&lunatik_deferlist);

	defer->finalize = finalize;
	llist_add(&defer->node, &list->items);
	irq_work_queue(&list->irq); /* a queue_work here would wake a kworker under a runqueue lock */
}

#define lunatik_foreachdeferirq(op, ...)					\
do {										\
	int cpu;								\
	for_each_possible_cpu(cpu)						\
		op(&per_cpu_ptr(&lunatik_deferlist, cpu)->irq, ## __VA_ARGS__);	\
} while (0)

int lunatik_setupdefer(void)
{
	lunatik_initdeferlist();
	lunatik_wq = alloc_workqueue("lunatik", WQ_UNBOUND, 0);
	return lunatik_wq != NULL ? 0 : -ENOMEM;
}

void lunatik_cleanupdefer(void)
{
	/* lunatik_deferirq may not have run yet, and it queues on the workqueue destroyed below */
	lunatik_foreachdeferirq(irq_work_sync);
	destroy_workqueue(lunatik_wq);
}

