/*
* SPDX-FileCopyrightText: (c) 2025-2026 Jieming Zhou <qrsikno@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* High-level Lua interface to the Linux HID subsystem.
* This module allows registering Lua table with functions as a HID driver,
* support for id_table is provided, which allows matching HID devices
*
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
* This is a userdata object returned by `hid.register()`. It encapsulates
* the kernel `struct hid_driver` and associated Lunatik runtime information
* necessary to invoke the Lua callback when a HID device is matched.
* The `registered` field indicates whether the driver is currently registered
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
	int ret;
} luahid_ctx_t;

static void luahid_release(void *private)
{
	luahid_t *hid = (luahid_t *)private;
	if (hid->registered)
		hid_unregister_driver(&hid->driver);

	lunatik_object_t *runtime = hid->runtime;
	if (runtime != NULL) {
		luadata_detach(runtime, hid, data);
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

static const luaL_Reg luahid_mt[] = {
	{"__gc", lunatik_deleteobject},
	{NULL, NULL},
};

static const lunatik_class_t luahid_class = {
	.name = "hid",
	.methods = luahid_mt,
	.release = luahid_release,
	.sleep = false,
	.shared = true,
};

static const struct hid_device_id *luahid_setidtable(lua_State *L, int idx)
{
	size_t len = luaL_len(L, idx);
	struct hid_device_id *user_table = lunatik_checkalloc(L, sizeof(struct hid_device_id) * (len + 1));

	struct hid_device_id *cur_id = user_table;
	for (size_t i = 0; i < len; i++, cur_id++) {
		if (lua_geti(L, idx, i + 1) != LUA_TTABLE) { /* table entry */
			lua_pop(L, 1); /* table entry */
			lunatik_free(user_table);
			user_table = NULL;
			goto out;
		}

		lunatik_optinteger(L, -1, cur_id, bus, HID_BUS_ANY);
		lunatik_optinteger(L, -1, cur_id, group, HID_GROUP_ANY);
		lunatik_optinteger(L, -1, cur_id, vendor, HID_ANY_ID);
		lunatik_optinteger(L, -1, cur_id, product, HID_ANY_ID);
		lunatik_optinteger(L, -1, cur_id, driver_data, 0);

		lua_pop(L, 1); /* table entry */
	}

	memset(cur_id, 0, sizeof(struct hid_device_id));
out:
	lua_pop(L, 1); /* id_table */
	return user_table;
}

#define luahid_setfield(L, idx, obj, field)	\
do { 						\
	lua_pushinteger(L, obj->field);		\
	lua_setfield(L, idx - 1, #field);	\
} while (0)

static inline int luahid_pcall(lua_State *L, lua_CFunction op, luahid_ctx_t *ctx)
{
	lua_pushcfunction(L, op);
	lua_pushlightuserdata(L, ctx);

	ctx->ret = 0;
	if (lua_pcall(L, 1, 0, 0) != LUA_OK)
		hid_err(ctx->hdev, "%s: %s\n", ctx->cb, lua_tostring(L, -1));
	return ctx->ret;
}

#define luahid_run(op, ctx, hid, hdev, ret)					\
do { 										\
	(ctx)->cb = #op; (ctx)->hid = hid; (ctx)->hdev = hdev;			\
	lunatik_run(hid->runtime, luahid_pcall, ret, luahid_do##op, ctx);	\
} while (0)

#define luahid_pushid(L, id, extra)		\
do { 						\
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

static inline lunatik_object_t *luahid_pushdata(lua_State *L, luahid_ctx_t *ctx)
{
	lunatik_object_t *obj;

	if (lunatik_getregistry(L, ctx->hid->data) != LUA_TUSERDATA ||
	    unlikely((obj = lunatik_toobject(L, -1)) == NULL)) {
		ctx->ret = -ENXIO;
		luaL_error(L, "couldn't find data");
	}

	luadata_reset(obj, ctx->data, 0, ctx->size, LUADATA_OPT_NONE);
	return obj;
}

static void luahid_op(lua_State *L, luahid_ctx_t *ctx, int nargs)
{
	luahid_t *hid = ctx->hid;
	int base = lua_gettop(L) - nargs;

	if (luahid_checkdriver(L, hid)) { /* stack: args, hid */
		ctx->ret = -ENXIO;
		luaL_error(L, "couldn't find driver");
	}

	lunatik_optcfunction(L, -1, ctx->cb, lunatik_nop); /* stack: args, hid, hid.cb */

	lua_insert(L, base + 1); /* hid.cb */
	lua_insert(L, base + 2); /* hid */
	lua_settop(L, base + 2 + nargs); /* stack: hid.cb, hid, args */

	if (lua_pcall(L, nargs + 1, 0, 0) != LUA_OK) { /* ops.cb(hid, args) */
		ctx->ret = -ECANCELED;
		lua_error(L);
	}
}

static int luahid_doprobe(lua_State *L)
{
	luahid_ctx_t *ctx = lua_touserdata(L, 1);

	luahid_pushid(L, ctx->id, driver_data);
	luahid_op(L, ctx, 1);
	return 0;
}

static int luahid_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	luahid_t *hid = luahid_gethid(hdev);
	luahid_ctx_t ctx = {.id = id};
	int ret;

	luahid_run(probe, &ctx, hid, hdev, ret);
	if (ret != 0 || (ret = hid_parse(hdev)) != 0)
		return ret;

	hid_set_drvdata(hdev, hid);
	return hid_hw_start(hdev, HID_CONNECT_DEFAULT);
}

static int luahid_doreport_fixup(lua_State *L)
{
	luahid_ctx_t *ctx = lua_touserdata(L, 1);
	const struct hid_device *hdev = ctx->hdev;

	luahid_pushhdev(L, hdev);
	lunatik_object_t *data = luahid_pushdata(L, ctx);
	luahid_op(L, ctx, 2);
	luadata_clear(data);
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
	const struct hid_device *hdev = ctx->hdev;

	luahid_pushhdev(L, hdev);
	luahid_pushreport(L, ctx->report);
	lunatik_object_t *data = luahid_pushdata(L, ctx);
	luahid_op(L, ctx, 3);
	luadata_clear(data);
	return 0;
}

static int luahid_raw_event(struct hid_device *hdev, struct hid_report *report, u8 *data, int size)
{
	luahid_t *hid = luahid_gethid(hdev);
	luahid_ctx_t ctx = {.data = data, .size = size, .report = report};
	int ret;

	luahid_run(raw_event, &ctx, hid, hdev, ret);
	return ret;
}

/***
* Registers a new HID driver.
* This function creates a new HID driver object from a Lua table and registers it with the kernel.
* The Lua table must contain the following fields:
*
* - `name`: The name of the driver (string).
* - `id_table`: A table of device IDs that this driver can match against (lua_table).
* 	- each id is a table consisting of fields:
*
* 		- `bus`: The bus type (integer, default: `HID_BUS_ANY`).
* 		- `group`: The group type (integer, default: `HID_GROUP_ANY`).
* 		- `vendor`: The vendor ID (integer, default: `HID_ANY_ID`).
* 		- `product`: The product ID (integer, default: `HID_ANY_ID`).
* 		- `driver_data`: Additional driver data (integer, default: `0`).
*
* @function hid.register
* @tparam table table The Lua table containing driver information.
* @treturn hid_driver The registered HID driver object.
* @see examples/gesture.lua
* @see examples/xiaomi.lua
*/
static int luahid_register(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);

	lunatik_object_t *object = lunatik_newobject(L, &luahid_class, sizeof(luahid_t));
	luahid_t *hid = (luahid_t *)object->private;
	memset(hid, 0, sizeof(luahid_t));

	struct hid_driver *driver = &(hid->driver);
	driver->name = lunatik_checkalloc(L, NAME_MAX);
	lunatik_setstring(L, 1, driver, name, NAME_MAX);

	lunatik_checkfield(L, 1, "id_table", LUA_TTABLE);
	luaL_argcheck(L, (driver->id_table = luahid_setidtable(L, -1)) != NULL, 1, "invaild id_table");

	driver->probe = luahid_probe;
	driver->report_fixup = luahid_report_fixup;
	driver->raw_event = luahid_raw_event;

	lunatik_setruntime(L, hid, hid);
	luadata_attach(L, hid, data);
	lunatik_getobject(hid->runtime);
	lunatik_registerobject(L, 1, object);

	if (hid_register_driver(driver) != 0) {
		lunatik_unregisterobject(L, object);
		luaL_error(L, "failed to register hid driver: %s", driver->name);
	}

	hid->registered = true;
	return 1; /* object */
}

LUNATIK_NEWLIB(hid, luahid_lib, &luahid_class, NULL);

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
MODULE_AUTHOR("Jieming Zhou <qrsikno@gmail.com>");

