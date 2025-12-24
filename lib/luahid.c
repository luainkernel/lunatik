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

#define luahid_pcall(L, func, hdev, arg) 				\
do { 									\
	int n = lua_gettop(L); 						\
	lua_pushcfunction(L, func); 					\
	lua_pushlightuserdata(L, (void *)hdev); 			\
	lua_pushlightuserdata(L, (void *)arg); 				\
	if (lua_pcall(L, 2, LUA_MULTRET, 0) != LUA_OK) { 		\
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

static inline void luahid_pushhdev(lua_State *L, struct hid_device *hdev)
{
	luahid_newtable(L, hdev, version);
	lua_pushstring(L, hdev->name);
	lua_setfield(L, -2, "name");
}

static inline void luahid_pushinfo(lua_State *L, int idx, struct hid_device *hdev)
{
	lua_pushlightuserdata(L, hdev);
	lua_rawget(L, idx - 1);
}

static inline void luahid_pushreport(lua_State *L, struct hid_report *report)
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

#define luahid_checkdriver(L, hid, idx, field) (lunatik_getregistry(L, hid) != LUA_TTABLE || \
	lua_getfield(L, idx, "ops") != LUA_TTABLE || lua_getfield(L, idx - 1, field) != LUA_TTABLE)

static inline lunatik_object_t *luahid_getdescriptor(lua_State *L, luahid_t *hid)
{
	lunatik_object_t *data;
	if (lunatik_getregistry(L, hid->descriptor) != LUA_TUSERDATA || unlikely((data = (lunatik_object_t *)lunatik_toobject(L, -1)) == NULL)) {
		pr_err("could not find descriptor\n");
		return NULL;
	}
	return data;
}

typedef struct hid_device_id luahid_probe_arg_t;

typedef struct {
	__u8 *rdesc;
	unsigned int rsize;
} luahid_report_fixup_arg_t;

typedef struct {
	struct hid_report *report;
	u8 *data;
	int size;
} luahid_raw_event_arg_t;

#define LUAHID_ARG(L, name, ix)	((luahid_##name##_arg_t *)lua_touserdata(L, ix))

static void luahid_preprobe(lua_State *L, struct hid_device *hdev, luahid_probe_arg_t *arg)
{
	luahid_newtable(L, arg, driver_data);
}

static void luahid_prereport_fixup(lua_State *L, struct hid_device *hdev, luahid_report_fixup_arg_t *arg)
{
	luahid_pushhdev(L, hdev);
	luahid_pushinfo(L, -4, hdev);
	lunatik_object_t *data = luahid_getdescriptor(L, luahid_gethid(hdev));
	if (data)
		luadata_reset(data, arg->rdesc, arg->rsize, LUADATA_OPT_NONE);
}

static void luahid_preraw_event(lua_State *L, struct hid_device *hdev, luahid_raw_event_arg_t *arg)
{
	luahid_pushhdev(L, hdev);
	luahid_pushinfo(L, -4, hdev);
	luahid_pushreport(L, arg->report);
	lunatik_object_t *data = luahid_getdescriptor(L, luahid_gethid(hdev));
	if (data)
		luadata_reset(data, arg->data, arg->size, LUADATA_OPT_NONE);
}

static void luahid_postprobe(lua_State *L, struct hid_device *hdev, luahid_probe_arg_t *arg)
{
	if (lua_istable(L, -1)) {
		lua_pushlightuserdata(L, hdev);
		lua_pushvalue(L, -2);
		lua_settable(L, -4);
		hid_set_drvdata(hdev, luahid_gethid(hdev));
	}
	lua_pushinteger(L, 0);
}

static void luahid_postreport_fixup(lua_State *L, struct hid_device *hdev, luahid_report_fixup_arg_t *arg)
{
	lunatik_object_t *data = luahid_getdescriptor(L, luahid_gethid(hdev));
	if (data)
		luadata_clear(data);
}

static void luahid_postraw_event(lua_State *L, struct hid_device *hdev, luahid_raw_event_arg_t *arg)
{
	lunatik_object_t *data = luahid_getdescriptor(L, luahid_gethid(hdev));
	if (data)
		luadata_clear(data);
	if (!lua_isboolean(L, -1))
		lua_pushinteger(L, -EINVAL);
	else
		lua_pushinteger(L, 0);
}

#define LUAHID_CALLBACK(NAME, NARG, NRET, LEVEL)							\
static int luahid_do##NAME(lua_State *L)								\
{													\
	struct hid_device *hdev = (struct hid_device *)lua_touserdata(L, 1);				\
	luahid_##NAME##_arg_t *arg = LUAHID_ARG(L, NAME, 2);						\
	luahid_t *hid = luahid_gethid(hdev);								\
													\
	if (luahid_checkdriver(L, hid, -1, "_info")) {							\
		pr_##LEVEL(#NAME ": invaild driver\n");							\
		if (NRET) lua_pushinteger(L, -ENXIO);							\
		return (NRET) ? 1 : 0;                   						\
	}												\
													\
	if (lua_getfield(L, -2, #NAME) != LUA_TFUNCTION) {						\
		if (NRET) lua_pushinteger(L, 0);							\
		return (NRET) ? 1 : 0;                   						\
	}                                                                      				\
													\
	lua_pushvalue(L, -3);                                                  				\
	luahid_pre##NAME(L, hdev, arg);                               					\
													\
	if (lua_pcall(L, NARG, NRET, 0) != LUA_OK) {                           				\
		pr_##LEVEL(#NAME ": %s\n", lua_tostring(L, -1));					\
		if (NRET) lua_pushinteger(L, -ECANCELED);						\
		return (NRET) ? 1 : 0;                   						\
	}												\
													\
	luahid_post##NAME(L, hdev, arg);								\
	return NRET;                                                           				\
}

LUAHID_CALLBACK(probe, 2, 1, err);
LUAHID_CALLBACK(report_fixup, 4, 0, warn);
LUAHID_CALLBACK(raw_event, 5, 1, err);

static int luahid_runprobe(lua_State *L, struct hid_device *hdev, luahid_probe_arg_t *arg)
{
	luahid_pcall(L, luahid_doprobe, hdev, arg);
	return lua_tointeger(L, -1);
}

static int luahid_probe(struct hid_device *hdev, const struct hid_device_id *id)
{
	luahid_t *hid = luahid_gethid(hdev);
	int ret;

	lunatik_run(hid->runtime, luahid_runprobe, ret, hdev, (luahid_probe_arg_t *)id);
	if (ret != 0 || (ret = hid_parse(hdev)) != 0)
		return ret;

	return hid_hw_start(hdev, HID_CONNECT_DEFAULT);
}

static int luahid_runreport_fixup(lua_State *L, struct hid_device *hdev, luahid_report_fixup_arg_t *arg)
{
	luahid_pcall(L, luahid_doreport_fixup, hdev, arg);
	return 0;
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 12, 0))
typedef const __u8* luahid_ret_t;
#else
typedef __u8* luahid_ret_t;
#endif

static luahid_ret_t luahid_report_fixup(struct hid_device *hdev, __u8 *rdesc, unsigned int *rsize)
{
	luahid_t *hid = luahid_gethid(hdev);
	int ret;
	luahid_report_fixup_arg_t arg;
	arg.rdesc = rdesc;
	arg.rsize = *rsize;

	lunatik_run(hid->runtime, luahid_runreport_fixup, ret, hdev, &arg);
	return rdesc;
}

static int luahid_runraw_event(lua_State *L, struct hid_device *hdev, luahid_raw_event_arg_t *arg, int *ret_bool)
{
	luahid_pcall(L, luahid_doraw_event, hdev, arg);
	int ret = lua_tointeger(L, -1);
	*ret_bool = ret ? false : lua_toboolean(L, -2);
	return ret;
}

static int luahid_raw_event(struct hid_device *hdev, struct hid_report *report, u8 *data, int size)
{
	luahid_t *hid = luahid_gethid(hdev);
	int ret, ret_bool = false;
	luahid_raw_event_arg_t arg;
	arg.report = report;
	arg.data = data;
	arg.size = size;

	lunatik_runirq(hid->runtime, luahid_runraw_event, ret, hdev, &arg, &ret_bool);
	return ret_bool;
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

