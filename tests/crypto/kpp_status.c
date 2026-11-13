/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* An ecdh-nist-p256, lunatik-kpp-status, which kpp_status.sh builds and loads for crypto.kpp to meet
* an engine's error status, the positive code atmel-ecc answers: no test host carries its chip.
*/

#include <crypto/ecdh.h>
#include <crypto/internal/kpp.h>
#include <linux/module.h>
#include <linux/workqueue.h>

#define STATUS_KEYSIZE	32 /* a P-256 scalar */
#define STATUS_FAULT	0x05 /* the "ECC Fault" atmel_i2c_status answers */

/* the keys kpp_status.lua names; every other key, the self-test's among them, the fallback serves */
static const u8 status_refused[STATUS_KEYSIZE] = {[0 ... STATUS_KEYSIZE - 1] = 0x01};
static const u8 status_faulty[STATUS_KEYSIZE] = {[0 ... STATUS_KEYSIZE - 1] = 0x02};

typedef struct status_ctx_s {
	struct crypto_kpp *fallback;
	bool faulty;
} status_ctx_t;

/* one request in flight: kpp_status.lua calls one method at a time */
static struct kpp_request *status_request;

static void status_complete(struct work_struct *work)
{
	kpp_request_complete(status_request, STATUS_FAULT);
}

static DECLARE_DELAYED_WORK(status_work, status_complete);

static bool status_iskey(const struct ecdh *params, const u8 *key)
{
	return params->key_size == STATUS_KEYSIZE && memcmp(params->key, key, STATUS_KEYSIZE) == 0;
}

/* atmel_ecdh_set_secret answers the status of the chip that refused a key generation */
static int status_set_secret(struct crypto_kpp *tfm, const void *buffer, unsigned int len)
{
	status_ctx_t *ctx = kpp_tfm_ctx(tfm);
	struct ecdh params;

	if (crypto_ecdh_decode_key(buffer, len, &params) < 0)
		return -EINVAL;
	if (status_iskey(&params, status_refused))
		return STATUS_FAULT;
	ctx->faulty = status_iskey(&params, status_faulty);
	return crypto_kpp_set_secret(ctx->fallback, buffer, len);
}

/* the caller's request moves to the fallback, as atmel_ecdh_generate_public_key moves it */
static struct kpp_request *status_fallback(struct kpp_request *request)
{
	status_ctx_t *ctx = kpp_tfm_ctx(crypto_kpp_reqtfm(request));

	kpp_request_set_tfm(request, ctx->fallback);
	return request;
}

static int status_generate_public_key(struct kpp_request *request)
{
	status_ctx_t *ctx = kpp_tfm_ctx(crypto_kpp_reqtfm(request));

	return ctx->faulty ? STATUS_FAULT : crypto_kpp_generate_public_key(status_fallback(request));
}

/* atmel_ecdh_done completes the request with the chip's status, from a worker */
static int status_compute_shared_secret(struct kpp_request *request)
{
	status_ctx_t *ctx = kpp_tfm_ctx(crypto_kpp_reqtfm(request));

	if (!ctx->faulty)
		return crypto_kpp_compute_shared_secret(status_fallback(request));
	status_request = request;
	/* after the caller's wait begins, whatever the preemption model */
	schedule_delayed_work(&status_work, msecs_to_jiffies(10));
	return -EINPROGRESS;
}

static unsigned int status_max_size(struct crypto_kpp *tfm)
{
	status_ctx_t *ctx = kpp_tfm_ctx(tfm);

	return crypto_kpp_maxsize(ctx->fallback);
}

static int status_init(struct crypto_kpp *tfm)
{
	status_ctx_t *ctx = kpp_tfm_ctx(tfm);
	struct crypto_kpp *fallback = crypto_alloc_kpp("ecdh-nist-p256-generic", 0, 0);

	if (IS_ERR(fallback))
		return PTR_ERR(fallback);
	ctx->fallback = fallback;
	return 0;
}

static void status_exit(struct crypto_kpp *tfm)
{
	status_ctx_t *ctx = kpp_tfm_ctx(tfm);

	crypto_free_kpp(ctx->fallback);
}

static struct kpp_alg status_alg = {
	.set_secret = status_set_secret,
	.generate_public_key = status_generate_public_key,
	.compute_shared_secret = status_compute_shared_secret,
	.max_size = status_max_size,
	.init = status_init,
	.exit = status_exit,
	.base = {
		.cra_name = "ecdh-nist-p256",
		.cra_driver_name = "lunatik-kpp-status",
		.cra_priority = 1, /* below the generic driver's, so the name alone never reaches this one */
		.cra_module = THIS_MODULE,
		.cra_ctxsize = sizeof(status_ctx_t),
	},
};

static int __init status_init_module(void)
{
	return crypto_register_kpp(&status_alg);
}

static void __exit status_exit_module(void)
{
	crypto_unregister_kpp(&status_alg);
	cancel_delayed_work_sync(&status_work); /* the worker may still be returning through this module */
}

module_init(status_init_module);
module_exit(status_exit_module);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_DESCRIPTION("An ecdh-nist-p256 answering an engine's error status for the crypto suite's kpp_status test");

