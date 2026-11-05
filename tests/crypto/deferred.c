/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* An asynchronous acomp, lunatik-deferred, which deferred.sh builds and loads for crypto.comp to wait
* on: no software acomp completes asynchronously, and no test host carries an engine.
*/

#include <crypto/internal/acompress.h>
#include <linux/module.h>
#include <linux/scatterlist.h>
#include <linux/workqueue.h>

/* one request in flight: deferred.lua calls one method at a time */
static struct acomp_req *deferred_request;
static bool deferred_backlogged;

static unsigned int completed;
module_param(completed, uint, 0444);
MODULE_PARM_DESC(completed, "requests the worker completed");

static int deferred_copy(struct acomp_req *request)
{
	if (request->dlen < request->slen)
		return -EINVAL;
	/* crypto.comp maps one linear block per side */
	memcpy(sg_virt(request->dst), sg_virt(request->src), request->slen);
	request->dlen = request->slen;
	return 0;
}

static void deferred_complete(struct work_struct *work)
{
	struct acomp_req *request = deferred_request;

	if (deferred_backlogged) /* the request leaves the backlog */
		acomp_request_complete(request, -EINPROGRESS);
	completed++;
	acomp_request_complete(request, deferred_copy(request));
}

static DECLARE_DELAYED_WORK(deferred_work, deferred_complete);

static int deferred_queue(struct acomp_req *request, bool backlogged)
{
	deferred_request = request;
	deferred_backlogged = backlogged;
	/* after the caller's wait begins, whatever the preemption model */
	schedule_delayed_work(&deferred_work, msecs_to_jiffies(10));
	return backlogged ? -EBUSY : -EINPROGRESS;
}

static int deferred_compress(struct acomp_req *request)
{
	return deferred_queue(request, false);
}

/* a full queue, as qat_alg_send_message answers: backlogged with CRYPTO_TFM_REQ_MAY_BACKLOG, refused without */
static int deferred_decompress(struct acomp_req *request)
{
	if (!(request->base.flags & CRYPTO_TFM_REQ_MAY_BACKLOG))
		return -ENOSPC;
	return deferred_queue(request, true);
}

static struct acomp_alg deferred_algs[] = {
	{
		.compress = deferred_compress,
		.decompress = deferred_decompress,
		.base = {
			.cra_name = "lunatik-deferred",
			.cra_driver_name = "lunatik-deferred-async",
			.cra_priority = 200,
			.cra_flags = CRYPTO_ALG_ASYNC,
			.cra_module = THIS_MODULE,
		},
	},
	/* the synchronous fallback 6.15 and later allocate beside an asynchronous transform */
	{
		.compress = deferred_copy,
		.decompress = deferred_copy,
		.base = {
			.cra_name = "lunatik-deferred",
			.cra_driver_name = "lunatik-deferred-sync",
			.cra_priority = 100,
			.cra_module = THIS_MODULE,
		},
	},
};

static int __init deferred_init(void)
{
	return crypto_register_acomps(deferred_algs, ARRAY_SIZE(deferred_algs));
}

static void __exit deferred_exit(void)
{
	crypto_unregister_acomps(deferred_algs, ARRAY_SIZE(deferred_algs));
	cancel_delayed_work_sync(&deferred_work); /* the worker may still be returning through this module */
}

module_init(deferred_init);
module_exit(deferred_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_DESCRIPTION("An asynchronous acomp the crypto suite's deferred test waits on");

