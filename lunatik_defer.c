/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/cpuhotplug.h>
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

static inline void lunatik_queuefinalize(void)
{
	queue_work(lunatik_wq, &lunatik_deferwork);
}

static void lunatik_deferirq(struct irq_work *irq)
{
	lunatik_queuefinalize();
}

/* an offline CPU takes no interrupt, so an irq_work queued there stays pending and irq_work_sync spins on it */
#define lunatik_isonline()	cpu_online(smp_processor_id())

void lunatik_defer(lunatik_defer_t *defer, lunatik_finalize_t finalize)
{
	lunatik_deferlist_t *list = this_cpu_ptr(&lunatik_deferlist);

	defer->finalize = finalize;
	llist_add(&defer->node, &list->items);
	if (lunatik_isonline())
		irq_work_queue(&list->irq); /* a queue_work here would wake a kworker under a runqueue lock */
}

#define lunatik_foreachdeferirq(op, ...)					\
do {										\
	int cpu;								\
	for_each_possible_cpu(cpu)						\
		op(&per_cpu_ptr(&lunatik_deferlist, cpu)->irq, ## __VA_ARGS__);	\
} while (0)

/* a CPU that is not online defers with no irq_work, so its list would wait for another CPU's deferral */
static int lunatik_deferhotplug(unsigned int cpu)
{
	lunatik_queuefinalize();
	return 0;
}

static int lunatik_deadstate, lunatik_onlinestate;

static int lunatik_setuphotplug(void)
{
	lunatik_deadstate = cpuhp_setup_state_nocalls(CPUHP_BP_PREPARE_DYN, "lunatik:dead", NULL, lunatik_deferhotplug);
	if (lunatik_deadstate < 0)
		return lunatik_deadstate;

	lunatik_onlinestate = cpuhp_setup_state_nocalls(CPUHP_AP_ONLINE_DYN, "lunatik:online", lunatik_deferhotplug, NULL);
	if (lunatik_onlinestate < 0) {
		cpuhp_remove_state_nocalls(lunatik_deadstate);
		return lunatik_onlinestate;
	}
	return 0;
}

static void lunatik_cleanuphotplug(void)
{
	cpuhp_remove_state_nocalls(lunatik_onlinestate);
	cpuhp_remove_state_nocalls(lunatik_deadstate);
}

int lunatik_setupdefer(void)
{
	lunatik_initdeferlist();
	lunatik_wq = alloc_workqueue("lunatik", WQ_UNBOUND, 0);
	if (lunatik_wq == NULL)
		return -ENOMEM;

	int ret = lunatik_setuphotplug();
	if (ret < 0)
		destroy_workqueue(lunatik_wq);
	return ret;
}

void lunatik_cleanupdefer(void)
{
	lunatik_cleanuphotplug();
	/* lunatik_deferirq may not have run yet, and it queues on the workqueue destroyed below */
	lunatik_foreachdeferirq(irq_work_sync);
	/* what a CPU defers past cpuhp_ap_report_dead, after lunatik_deferhotplug ran, would outlive the module */
	lunatik_queuefinalize();
	destroy_workqueue(lunatik_wq);
}

