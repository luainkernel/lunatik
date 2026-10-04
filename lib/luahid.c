/*
* SPDX-FileCopyrightText: (c) 2025-2026 Jieming Zhou <qrsikno@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Writes a HID driver in Lua: it matches devices by `id_table`, and can fix a
* device's report descriptor and rewrite its raw reports.
*
* The driver's runtime is softirq: the script runs with
* `lunatik run -c softirq <script>`, other contexts raise
* `runtime context mismatch`, and the callbacks, which run under that runtime's
* lock, must not sleep. The driver stays registered until its `stop` or the end of
* the runtime.
*
* See `examples/gesture` and `examples/xiaomi`.
* @usage
*   -- run with `lunatik run -c softirq <script>`
*   local hid = require("hid")
*
*   local function raw_event(driver, hdev, report, raw)
*     print(hdev.name, report.id, #raw)
*   end
*
*   hid.register({
*     name = "luahid_trace",
*     id_table = {{bus = 0x05, vendor = 0x2717, product = 0x5014}},
*     raw_event = raw_event,
*   })
* @module hid
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/version.h>
#include <linux/string.h>
#include <linux/hid.h>

#include <lunatik.h>

#include "luadata.h"

/***
* Represents a registered HID driver.
* @type hid_driver
*/
typedef struct luahid_s {
	lunatik_object_t *runtime;
	lunatik_object_t *data;
	struct hid_driver driver;
	bool registered;
} luahid_t;

typedef struct luahid_ctx_s {
	const char *cb;
	luahid_t *hid;
	const struct hid_device *hdev;
	const struct hid_report *report;
	const struct hid_device_id *id;
	u8 *data;
	size_t size;
	lunatik_object_t *view;
	int ret;
} luahid_ctx_t;

static void luahid_release(void *private)
{
	luahid_t *hid = (luahid_t *)private;
	if (hid->registered)
		hid_unregister_driver(&hid->driver);

	lunatik_object_t *runtime = hid->runtime;
	if (runtime != NULL) {
		lunatik_detach(runtime, hid, data);
		lunatik_putobject(runtime);
	}
	if (hid->driver.id_table != NULL)
		lunatik_free(hid->driver.id_table);
	if (hid->driver.name != NULL)
		lunatik_free(hid->driver.name);
}

static int luahid_register(lua_State *L);

static const luaL_Reg luahid_lib[] = {
	{"register", luahid_register},
	{NULL, NULL},
};

static const lunatik_class_t luahid_class;

/***
* Unregisters the driver.
* The devices it drives are released from it, and no callback of it runs again. Calling it
* again does nothing, and a to-be-closed variable holding the driver stops it the same way.
* @function stop
* @treturn nil
* @raise "not allowed once the runtime is armed" past the script body: hid_unregister_driver
*   sleeps, and an armed runtime runs under its spinlock
* @usage driver:stop()
*/
static int luahid_stop(lua_State *L)
{
	lunatik_checkarmed(L);
	lunatik_stopobject(L, lunatik_checkobjectclass(L, 1, &luahid_class));
	return 0;
}

static const luaL_Reg luahid_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", luahid_stop},
	{"stop", luahid_stop},
	{NULL, NULL},
};

static const lunatik_class_t luahid_class = {
	.name = "hid",
	.methods = luahid_mt,
	.release = luahid_release,
	.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
	.owner = THIS_MODULE,
};

#define LUAHID_MAXIDS	(4096)
#define LUAHID_MAXDATA	((lua_Integer)min_t(u64, ULONG_MAX, LUA_MAXINTEGER))

static void luahid_setidtable(lua_State *L, int idx, struct hid_driver *driver)
{
	lunatik_checkfield(L, idx, "id_table", LUA_TTABLE);
	size_t len = luaL_len(L, -1);

	if (len > LUAHID_MAXIDS)
		luaL_error(L, "'id_table' is too long");

	struct hid_device_id *id_table = lunatik_checkalloc(L, sizeof(struct hid_device_id) * (len + 1));
	struct hid_device_id *cur_id = id_table;
	size_t i;

	driver->id_table = id_table; /* own id_table before the walk can raise, so release frees it */
	for (i = 0; i < len; i++, cur_id++) {
		luaL_argcheck(L, lua_geti(L, -1, i + 1) == LUA_TTABLE, idx, "invalid id_table"); /* table entry */

		lunatik_optinteger(L, -1, cur_id, bus, 0, U16_MAX, HID_BUS_ANY);
		lunatik_optinteger(L, -1, cur_id, group, 0, U16_MAX, HID_GROUP_ANY);
		lunatik_optinteger(L, -1, cur_id, vendor, 0, U32_MAX, HID_ANY_ID);
		lunatik_optinteger(L, -1, cur_id, product, 0, U32_MAX, HID_ANY_ID);
		lunatik_optinteger(L, -1, cur_id, driver_data, 0, LUAHID_MAXDATA, 0);

		lua_pop(L, 1); /* table entry */
	}

	memset(cur_id, 0, sizeof(struct hid_device_id));
	lua_pop(L, 1); /* id_table */
}

#define luahid_setfield(L, idx, obj, field)	\
do {						\
	lua_pushinteger(L, obj->field);		\
	lua_setfield(L, idx - 1, #field);	\
} while (0)

#define luahid_run(op, ctx, hid, hdev, ret)					\
do {										\
	(ctx)->cb = #op; (ctx)->hid = hid; (ctx)->hdev = hdev;			\
	lunatik_run(hid->runtime, lunatik_catch, ret, luahid_do##op, ctx,	\
		(ctx)->cb);							\
	if (ret == 0)								\
		ret = (ctx)->ret;						\
} while (0)

#define luahid_pushid(L, id, extra)		\
do {						\
	lua_newtable(L); 			\
	luahid_setfield(L, -1, id, bus); 	\
	luahid_setfield(L, -1, id, group); 	\
	luahid_setfield(L, -1, id, vendor); 	\
	luahid_setfield(L, -1, id, product); 	\
	luahid_setfield(L, -1, id, extra); 	\
} while (0)

static inline void luahid_pushhdev(lua_State *L, const struct hid_device *hdev)
{
	luahid_pushid(L, hdev, version);
	lua_pushstring(L, hdev->name);
	lua_setfield(L, -2, "name");
}

static inline void luahid_pushreport(lua_State *L, const struct hid_report *report)
{
	lua_newtable(L);
	luahid_setfield(L, -1, report, id);
	luahid_setfield(L, -1, report, type);
	luahid_setfield(L, -1, report, size);
	luahid_setfield(L, -1, report, application);
	luahid_setfield(L, -1, report, maxfield);
}

static luahid_t *luahid_gethid(struct hid_device *hdev)
{
	struct hid_driver *driver = hdev->driver;
	return container_of(driver, luahid_t, driver);
}

#define luahid_checkdriver(L, hid)	(lunatik_getregistry(L, hid) != LUA_TTABLE)

static inline void luahid_pushdata(lua_State *L, luahid_ctx_t *ctx)
{
	lunatik_object_t *obj = lunatik_getregistryobject(L, ctx->hid->data);

	if (unlikely(obj == NULL))
		luaL_error(L, "couldn't find data");

	luadata_reset(obj, ctx->data, ctx->size, LUADATA_OPT_NONE);
	ctx->view = obj;
}

static void luahid_op(lua_State *L, luahid_ctx_t *ctx, int nargs, int nresults)
{
	luahid_t *hid = ctx->hid;
	int base = lua_gettop(L) - nargs;

	if (luahid_checkdriver(L, hid)) /* stack: args, hid */
		luaL_error(L, "couldn't find driver");

	lunatik_optcfunction(L, -1, ctx->cb, lunatik_nop); /* stack: args, hid, hid.cb */

	lua_insert(L, base + 1); /* hid.cb */
	lua_insert(L, base + 2); /* hid */
	lua_settop(L, base + 2 + nargs); /* stack: hid.cb, hid, args */

	int status = lua_pcall(L, nargs + 1, nresults, 0); /* ops.cb(hid, args) */
	if (ctx->view != NULL)
		luadata_clear(ctx->view); /* the buffer is the kernel's, also when the callback raised */
	if (status != LUA_OK)
		lua_error(L);
}

static int luahid_doprobe(lua_State *L)
{
	luahid_ctx_t *ctx = lua_touserdata(L, 1);

	luahid_pushhdev(L, ctx->hdev);
	lua_pushvalue(L, -1);
	luahid_pushid(L, ctx->id, driver_data);
	luahid_op(L, ctx, 2, 1);
	ctx->ret = lunatik_opterrno(L, -1);
	if (ctx->ret == 0)
		lunatik_register(L, -2, ctx->hdev); /* a probe that fails gets no remove to drop it */
	return 0;
}

static int luahid_doremove(lua_State *L)
{
	luahid_ctx_t *ctx = lua_touserdata(L, 1);

	lunatik_getregistry(L, ctx->hdev); /* hdev */
	lunatik_unregister(L, ctx->hdev); /* before the callback, which may raise */
	luahid_op(L, ctx, 1, 0);
	return 0;
}

static void luahid_detach(luahid_t *hid, struct hid_device *hdev)
{
	luahid_ctx_t ctx = {0};
	int ret;

	luahid_run(remove, &ctx, hid, hdev, ret);
}

static int luahid_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	luahid_t *hid = luahid_gethid(hdev);
	luahid_ctx_t ctx = {.id = id};
	int ret;

	luahid_run(probe, &ctx, hid, hdev, ret);
	if (ret != 0)
		return ret;

	hid_set_drvdata(hdev, hid);
	if ((ret = hid_parse(hdev)) != 0 || (ret = hid_hw_start(hdev, HID_CONNECT_DEFAULT)) != 0)
		luahid_detach(hid, hdev); /* the HID core calls no remove after a failed probe */
	return ret;
}

static void luahid_remove(struct hid_device *hdev)
{
	hid_hw_stop(hdev);
	luahid_detach(luahid_gethid(hdev), hdev);
}

static int luahid_doreport_fixup(lua_State *L)
{
	luahid_ctx_t *ctx = lua_touserdata(L, 1);

	lunatik_getregistry(L, ctx->hdev); /* hdev */
	luahid_pushdata(L, ctx);
	luahid_op(L, ctx, 2, 0);
	return 0;
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 12, 0))
typedef const __u8 * luahid_rdesc_t;
#else
typedef __u8 * luahid_rdesc_t;
#endif

static luahid_rdesc_t luahid_report_fixup(struct hid_device *hdev, __u8 *rdesc, unsigned int *rsize)
{
	luahid_t *hid = luahid_gethid(hdev);
	luahid_ctx_t ctx = {.data = rdesc, .size = (size_t)*rsize};
	int ret;

	luahid_run(report_fixup, &ctx, hid, hdev, ret);
	return rdesc;
}

static int luahid_doraw_event(lua_State *L)
{
	luahid_ctx_t *ctx = lua_touserdata(L, 1);

	lunatik_getregistry(L, ctx->hdev); /* hdev */
	luahid_pushreport(L, ctx->report);
	luahid_pushdata(L, ctx);
	luahid_op(L, ctx, 3, 1);
	ctx->ret = lunatik_opterrno(L, -1);
	return 0;
}

static int luahid_raw_event(struct hid_device *hdev, struct hid_report *report, u8 *data, int size)
{
	luahid_t *hid = luahid_gethid(hdev);
	luahid_ctx_t ctx = {.data = data, .size = size, .report = report};
	int ret;

	luahid_run(raw_event, &ctx, hid, hdev, ret);
	return ret != 0 ? ret : ctx.ret;
}

static const char *const luahid_callbacks[] = {"probe", "report_fixup", "raw_event", "remove", NULL};

/***
* Registers a new HID driver.
* The `opts` table is the driver: each callback it carries receives it as its first
* argument, and one it does not carry does nothing.
* @function register
* @tparam table opts driver options: `name` (string), `id_table` (array of device ID tables,
*   each with optional integer fields `bus` and `group`, from 0 to `0xffff`, `vendor` and
*   `product`, from 0 to `0xffffffff`, and `driver_data`, from 0), and the optional callbacks:
*
*   - `probe(driver, hdev, id)`: a device matched; `hdev` is the device's table, made here
*     and handed to every later callback of the device, and `id` is the matching entry, with
*     `bus`, `group`, `vendor`, `product` and `driver_data`. Returning a negative errno,
*     `-errno.ENODEV` say, with `linux.errno`, fails the probe with it; an error, or a
*     return that is neither nothing, zero nor an errno a user program is given, the
*     kernel's own from `ERESTARTSYS` on, logged as `invalid errno`, fails it with
*     `ECANCELED`.
*   - `report_fixup(driver, hdev, rdesc)`: `rdesc` is a `data` over the report
*     descriptor, edited in place, of fixed size and valid only during the call.
*   - `raw_event(driver, hdev, report, raw)`: `raw` is a `data` over the report, edited
*     in place and valid only during the call. Returning nothing or zero passes the report
*     on and a negative errno drops it; an error, or any other return, drops it with
*     `ECANCELED`.
*   - `remove(driver, hdev)`: the device left the driver, or the HID core failed its probe
*     after `probe` returned, so each `probe` that returned gets one `remove`; a device the
*     driver still holds when its runtime stops gets none.
*
*   `hdev` carries `bus`, `group`, `vendor`, `product`, `version` and `name`, and keeps what
*   the callbacks store in it; `report` carries `id`, `type`, `size`, `application` and
*   `maxfield`. What `report_fixup` and `remove` return is ignored, and a callback's error
*   goes to the kernel log.
* @treturn hid_driver the driver, which `hid.register` keeps for its runtime: dropping it stops
*   nothing, and the driver stays registered until `stop` or the end of the runtime
* @raise "not allowed once the runtime is armed" past the script body; from a percpu runtime; if
*   required fields are missing, or `id_table` is invalid or too long; the kernel's errno if it
*   refuses the driver, `EBUSY` for a name another driver holds on the bus;
*   `bad field '<field>' (number expected, got <type>)` if an entry's `bus`, `group`, `vendor`,
*   `product` or `driver_data` is present and not a number, and
*   `bad field '<field>' (out of bounds)` if it is past its range;
*   `bad field '<field>' (function expected, got <type>)` if `probe`, `report_fixup`, `raw_event`
*   or `remove` is present and not a function; `runtime context mismatch`
*   unless the runtime is softirq; `not allowed while the runtime closes` from a finalizer that
*   runs at its close
* @within hid
*/
static int luahid_register(lua_State *L)
{
	lunatik_checkarmed(L);
	lunatik_checkpercpu(L);
	luaL_checktype(L, 1, LUA_TTABLE);
	lunatik_checkcallbacks(L, 1, luahid_callbacks);

	lunatik_object_t *object = lunatik_newobject(L, &luahid_class, sizeof(luahid_t), LUNATIK_OPT_NONE);
	luahid_t *hid = (luahid_t *)object->private;
	struct hid_driver *driver = &hid->driver;
	driver->name = lunatik_checkalloc(L, NAME_MAX);
	lunatik_setstring(L, 1, driver, name, NAME_MAX);

	luahid_setidtable(L, 1, driver);

	driver->probe = luahid_probe;
	driver->report_fixup = luahid_report_fixup;
	driver->raw_event = luahid_raw_event;
	driver->remove = luahid_remove;

	hid->runtime = lunatik_checkruntime(L, luahid_class.name, luahid_class.opt);
	lunatik_getobject(hid->runtime);
	lunatik_attach(L, hid, data, luadata_new, LUNATIK_OPT_SINGLE);
	lunatik_registerobject(L, 1, object);

	int ret = hid_register_driver(driver);
	if (ret != 0) {
		lunatik_unregisterobject(L, object);
		lunatik_throw(L, ret);
	}

	hid->registered = true;
	return 1; /* object */
}

LUNATIK_CLASSES(hid, &luahid_class);
LUNATIK_NEWLIB(hid, luahid_lib, luahid_classes);

static int __init luahid_init(void)
{
	return 0;
}

static void __exit luahid_exit(void)
{
}

module_init(luahid_init);
module_exit(luahid_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Jieming Zhou <qrsikno@gmail.com>");

