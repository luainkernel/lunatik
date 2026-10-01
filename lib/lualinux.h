/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lualinux_h
#define lualinux_h

#include <linux/pid_namespace.h>
#include <linux/nsproxy.h>
#include <linux/sched/task.h>
#include <net/net_namespace.h>

static inline struct net *lualinux_getnetbypid(pid_t pid)
{
	struct net *net = ERR_PTR(-ESRCH);

	rcu_read_lock();
	struct task_struct *task = pid_task(find_pid_ns(pid, &init_pid_ns), PIDTYPE_PID);
	if (task == NULL)
		goto unlock;

	task_lock(task);
	if (task->nsproxy != NULL)
		net = get_net(task->nsproxy->net_ns);
	task_unlock(task);
unlock:
	rcu_read_unlock();
	return net;
}

#endif

