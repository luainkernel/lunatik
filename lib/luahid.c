/*
* SPDX-FileCopyrightText: (c) 2025 Jieming Zhou <qrsikno@gmail.com>
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
#include <lauxlib.h>

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
	lunatik_object_t *descriptor;
	lunatik_object_t *raw_event;
	struct hid_driver driver;
	bool registered;
} luahid_t;


static void luahid_release(void *private)
{
	luahid_t *hid = (luahid_t *)private;
	if (hid->registered)
		hid_unregister_driver(&hid->driver);
	if (hid->runtime != NULL)
		lunatik_putobject(hid->runtime);
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

#define luahid_pcall(L, func, arg) 					\
do { 									\
	int n = lua_gettop(L); 						\
	lua_pushcfunction(L, func); 					\
	lua_pushlightuserdata(L, (void *)arg); 				\
	if (lua_pcall(L, 1, LUA_MULTRET, 0) != LUA_OK) { 		\
		pr_warn("%s: %s\n", #func, lua_tostring(L, -1));	\
		lua_settop(L, n);					\
	} 								\
} while (0)

#define luahid_newtable(L, dev, extra)			\
do { 							\
	lua_newtable(L); 				\
	luahid_setfield(L, -1, dev, bus); 		\
	luahid_setfield(L, -1, dev, group); 		\
	luahid_setfield(L, -1, dev, vendor); 		\
	luahid_setfield(L, -1, dev, product); 		\
	luahid_setfield(L, -1, dev, extra); 		\
} while (0)

static inline int luahid_pushdevid(lua_State *L)
{
	struct hid_device_id *device_id = (struct hid_device_id *)lua_touserdata(L, 1);
	luahid_newtable(L, device_id, driver_data);
	return 1; /* devid table */
}

static inline int luahid_pushhdev(lua_State *L)
{
	struct hid_device *hdev = (struct hid_device *)lua_touserdata(L, 1);
	luahid_newtable(L, hdev, version);
	lua_pushstring(L, hdev->name);
	lua_setfield(L, -2, "name");
	return 1; /* hdev table */
}

static inline void luahid_pushinfo(lua_State *L, int idx, struct hid_device *hdev)
{
	lua_pushlightuserdata(L, hdev);
	lua_rawget(L, idx - 1);
}

static inline int luahid_pushreport(lua_State *L)
{
	struct hid_report *report = (struct hid_report *)lua_touserdata(L, 1);
	lua_newtable(L);
	luahid_setfield(L, -1, report, id);
	luahid_setfield(L, -1, report, type);
	luahid_setfield(L, -1, report, size);
	luahid_setfield(L, -1, report, application);
	luahid_setfield(L, -1, report, maxfield);
	return 1; /* report table */
}

#define luahid_checkdriver(L, hid, idx, field) (lunatik_getregistry(L, hid) != LUA_TTABLE || \
	lua_getfield(L, idx, "ops") != LUA_TTABLE || lua_getfield(L, idx - 1, field) != LUA_TTABLE)

static int luahid_doprobe(lua_State *L, luahid_t *hid, struct hid_device *hdev, const struct hid_device_id *id)
{
	if (luahid_checkdriver(L, hid, -1, "_info")) {
		pr_err("probe: couldn't find driver\n");
		return -ENXIO;
	}

	if (lua_getfield(L, -2, "probe") != LUA_TFUNCTION)
		return 0;

	lua_pushvalue(L, -3); /* hid.ops */
	luahid_pcall(L, luahid_pushdevid, id);

	if (lua_pcall(L, 2, 1, 0) != LUA_OK) {
		pr_err("probe: %s\n", lua_tostring(L, -1));
		return -ECANCELED;
	}

	if (lua_type(L, -1) == LUA_TTABLE) {
		lua_pushlightuserdata(L, hdev);
		lua_pushvalue(L, -2); /* returned table */
		lua_settable(L, -4); /* hid._info[hdev] = returned table */

		hid_set_drvdata(hdev, hid);
	}
	return 0;
}

static int luahid_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	struct hid_driver *driver = hdev->driver;
	luahid_t *hid = container_of(driver, luahid_t, driver);
	int ret;

	lunatik_run(hid->runtime, luahid_doprobe, ret, hid, hdev, id);
	if (ret != 0 || (ret = hid_parse(hdev)) != 0)
		return ret;

	return hid_hw_start(hdev, HID_CONNECT_DEFAULT);
}

static inline lunatik_object_t *luahid_getdescriptor(lua_State *L, luahid_t *hid)
{
	lunatik_object_t *data;
	if (lunatik_getregistry(L, hid->descriptor) != LUA_TUSERDATA || unlikely((data = (lunatik_object_t *)lunatik_toobject(L, -1)) == NULL)) {
		pr_err("could not find descriptor\n");
		return NULL;
	}
	return data;
}

static int luahid_doreport_fixup(lua_State *L, luahid_t *hid, struct hid_device *hdev, __u8 *rdesc, unsigned int rsize)
{
	if (luahid_checkdriver(L, hid, -1, "_info") || lua_getfield(L, -2, "report_fixup") != LUA_TFUNCTION) {
		pr_warn("report_fixup: invaild driver\n");
		goto out;
	}

	lua_pushvalue(L, -3); /* hid.ops */
	luahid_pcall(L, luahid_pushhdev, hdev);
	luahid_pushinfo(L, -4, hdev);

	lunatik_object_t *data;
	if ((data = luahid_getdescriptor(L, hid)) == NULL) {
		pr_warn("report_fixup: descriptor not found\n");
		goto out;
	}
	luadata_reset(data, rdesc, rsize, LUADATA_OPT_NONE);

	if (lua_pcall(L, 4, 0, 0) != LUA_OK)
		pr_warn("report_fixup: %s\n", lua_tostring(L, -1));

	luadata_clear(data);
out:
	return 0; /* unused  */
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 12, 0))
typedef const __u8* luahid_ret_t;
#else
typedef __u8* luahid_ret_t;
#endif

static luahid_ret_t luahid_report_fixup(struct hid_device *hdev, __u8 *rdesc, unsigned int *rsize)
{
	struct hid_driver *driver = hdev->driver;
	luahid_t *hid = container_of(driver, luahid_t, driver);
	int ret;

	lunatik_run(hid->runtime, luahid_doreport_fixup, ret, hid, hdev, rdesc, *rsize);
	return rdesc;
}

static inline lunatik_object_t *luahid_getrawdata(lua_State *L, luahid_t *hid)
{
	lunatik_object_t *data;
	if (lunatik_getregistry(L, hid->raw_event) != LUA_TUSERDATA || unlikely((data = (lunatik_object_t *)lunatik_toobject(L, -1)) == NULL)) {
		pr_err("could not find raw_event data\n");
		return NULL;
	}
	return data;
}

static int luahid_doraw_event(lua_State *L, luahid_t *hid, struct hid_device *hdev, struct hid_report *report, u8 *data, int size, int *ret)
{
	if (luahid_checkdriver(L, hid, -1, "_info")) {
		pr_err("raw_event: couldn't find driver");
		return -ENXIO;
	}

	if (lua_getfield(L, -2, "raw_event") != LUA_TFUNCTION)
		return 0;

	lua_pushvalue(L, -3);  /* hid.ops */
	luahid_pcall(L, luahid_pushhdev, hdev);
	luahid_pushinfo(L, -4, hdev);
	luahid_pcall(L, luahid_pushreport, report);
	lunatik_object_t *raw_data;
	if ((raw_data = luahid_getrawdata(L, hid)) == NULL) {
		pr_warn("raw_event: event data not found\n");
		return -ENXIO;
	}
	luadata_reset(raw_data, data, size, LUADATA_OPT_NONE);

	if (lua_pcall(L, 5, 1, 0) != LUA_OK) {
		pr_err("raw_event: %s\n", lua_tostring(L, -1));
		return -ECANCELED;
	}

	luadata_clear(raw_data);
	if (!lua_isboolean(L, -1))
		return -EINVAL;

	*ret = lua_toboolean(L, -1);
	return 0;
}

static int luahid_raw_event(struct hid_device *hdev, struct hid_report *report, u8 *data, int size)
{
	struct hid_driver *driver = hdev->driver;
	luahid_t *hid = container_of(driver, luahid_t, driver);
	int ret_bool = 0;
	int ret;
	unsigned long flags;

	local_irq_save(flags);
	lunatik_run(hid->runtime, luahid_doraw_event, ret, hid, hdev, report, data, size, &ret_bool);
	local_irq_restore(flags);
	return ret ? false : ret_bool;
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
* @usage
*	 local hid = require("hid")
*	 local hid_driver = {
*	 	name = "my_hid_driver",
*	 	id_table = {
*	 		{ bus = 1, vendor = 0x1234, product = 0x5678 },
*	 		{ bus = 2, vendor = 0x4321, product = 0x8765 },
*	 	}
*	 }
*
*	 function hid_driver:probe(devid)
*	 	drvdata = {}
*	 	if devid.bus == 1 then
*	 		drvdata.usb_feature = true
*	 	end
*	 	if devid.driver_data % 2 == 0 then
*	 		drvdata.even_special_feature = true
*	 	end
*	 	return drvdata
*	 end
*
*	 function hid_driver:report_fixup(hdev, priv_data, descriptor)
*	 	if hdev.vendor == 0x1234 and hdev.product == 0x5678 then
*	 		descriptor[1] = 0x05
*	 		descriptor[descriptor.size] = 0x0A
*	 	end
*	 end
*
*	 function hid_driver:raw_event(priv_data, report, raw_data)
*	 	print("Raw event received for report ID:", report.id)
*	 	return false
*	 end
*
*	 hid.register(hid_driver)
*/
static int luahid_register(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);

	lua_newtable(L); /* hid = {} */
	lua_pushvalue(L, 1);
	lua_setfield(L, 2, "ops"); /* hid.ops = table */
	lua_newtable(L);
	lua_setfield(L, 2, "_info"); /* hid._info = {} */

	lunatik_object_t *object = lunatik_newobject(L, &luahid_class, sizeof(luahid_t));
	luahid_t *hid = (luahid_t *)object->private;
	memset(hid, 0, sizeof(luahid_t));
	luadata_attach(L, hid, descriptor);
	luadata_attach(L, hid, raw_event);

	struct hid_driver *user_driver = &(hid->driver);
	user_driver->name = lunatik_checkalloc(L, NAME_MAX);
	lunatik_setstring(L, 1, user_driver, name, NAME_MAX);

	lunatik_checkfield(L, 1, "id_table", LUA_TTABLE);
	luaL_argcheck(L, (user_driver->id_table = luahid_setidtable(L, -1)) != NULL,
		      2, "invaild id_table");

	user_driver->probe = luahid_probe;
	user_driver->report_fixup = luahid_report_fixup;
	user_driver->raw_event = luahid_raw_event;

	lunatik_setruntime(L, hid, hid);
	lunatik_getobject(hid->runtime);
	lunatik_registerobject(L, 2, object);

	if (__hid_register_driver(user_driver, THIS_MODULE, KBUILD_MODNAME) != 0) {
		lunatik_unregisterobject(L, object);
		luaL_error(L, "failed to register hid driver: %s", user_driver->name);
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

