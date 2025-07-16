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
#include <string.h>
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
	struct hid_driver driver;
	bool registered;
} luahid_t;

typedef struct luadata_s {
	char *ptr;
	size_t size;
	uint8_t opt;
} luadata_t;

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
	.sleep = true,
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

static inline void luahid_pushdevid(lua_State *L, int idx, const struct hid_device_id *device_id)
{
	lua_newtable(L);
	luahid_setfield(L, -1, device_id, bus);
	luahid_setfield(L, -1, device_id, group);
	luahid_setfield(L, -1, device_id, vendor);
	luahid_setfield(L, -1, device_id, product);
	luahid_setfield(L, -1, device_id, driver_data);
}

static inline void luahid_pushhdev(lua_State *L, struct hid_device *hdev)
{
	lua_newtable(L);
	luahid_setfield(L, -1, hdev, bus);
	luahid_setfield(L, -1, hdev, group);
	luahid_setfield(L, -1, hdev, vendor);
	luahid_setfield(L, -1, hdev, product);
	luahid_setfield(L, -1, hdev, version);
	lua_pushstring(L, hdev->name);
	lua_setfield(L, -2, "name");
}

#define luahid_checkdriver(L, hid, idx, field) (lunatik_getregistry(L, hid) != LUA_TTABLE || \
	lua_getfield(L, idx, "ops") != LUA_TTABLE || lua_getfield(L, idx - 1, field) != LUA_TTABLE)

#define luahid_error(code, op, msg)		\
do {						\
	pr_err("%s: %s\n", (op), (msg)); 	\
	return code; 				\
} while (0)

static int luahid_doprobe(lua_State *L, luahid_t *hid, struct hid_device *hdev, const struct hid_device_id *id)
{
	if (luahid_checkdriver(L, hid, -1, "_info"))
		luahid_error(-ENXIO, "probe", "couldn't find driver");

	if (lua_getfield(L, -2, "probe") != LUA_TFUNCTION)
		return 0;

	lua_pushvalue(L, -3); /* hid.ops */
	luahid_pushdevid(L, -4, id);

	if (lua_pcall(L, 2, 1, 0) != LUA_OK)
		luahid_error(-ECANCELED, "probe", lua_tostring(L, -1));

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

static int luahid_doreport_fixup(lua_State *L, luahid_t *hid,
				 struct hid_device *hdev, __u8 *buf, unsigned int *size,
				 __u8 **ret_ptr)
{
	if (luahid_checkdriver(L, hid, -1, "_report"))
		luahid_error(-ENXIO, "report_fixup", "couldn't find driver");

	if (lua_getfield(L, -2, "report_fixup") != LUA_TFUNCTION)
		return -ENXIO;

	lua_pushvalue(L, -3); /* hid.ops */
	luahid_pushhdev(L, hdev);
	lunatik_object_t *original_data = luadata_new(buf, *size, hid->runtime->sleep, LUADATA_OPT_FREE);
	if (!original_data)
		luahid_error(-ENOMEM, "report_fixup", "failed to create luadata for original report");
	lunatik_pushobject(L, original_data);

	if (lua_pcall(L, 3, 1, 0) != LUA_OK)
		luahid_error(-ECANCELED, "report_fixup", lua_tostring(L, -1));

	if (lua_isnil(L, -1))
		return -ENXIO;

	lunatik_object_t *returned_object = lunatik_checkobject(L, -1);
	lua_pushlightuserdata(L, hdev);
	lua_pushvalue(L, -2); /* luadata */
	lua_settable(L, -4); /* hid._report[hdev] = luadata */

	luadata_t *data = (luadata_t *)returned_object->private;
	*size = data->size;
	*ret_ptr = data->ptr;

	return 0;
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 12, 0))
#define LUAHID_RET const __u8 *
#else
#define LUAHID_RET __u8 *
#endif

static LUAHID_RET luahid_report_fixup(struct hid_device *hdev, __u8 *buf, unsigned int *size)
{
	struct hid_driver *driver = hdev->driver;
	luahid_t *hid = container_of(driver, luahid_t, driver);
	__u8 *ret_ptr = buf;
	int ret;

	lunatik_run(hid->runtime, luahid_doreport_fixup, ret, hid, hdev, buf, size, &ret_ptr);

	return ret ? buf : ret_ptr;
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
*	 function hid_driver:report_fixup(hdev, original_report)
*	 	if hdev.vendor == 0x1234 and hdev.product == 0x5678 then
*	 		len = #original_report
*	 		ret = original_report:dup(len + 1)
*	 		ret:setbyte(1, 0x05)
*	 		ret:setbyte(len, 0x0A)
*	 		return ret
*	 	end
*	 	return original_report
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

	lua_newtable(L);
	lua_setfield(L, 2, "_report"); /* hid._report = {} */

	lunatik_object_t *object = lunatik_newobject(L, &luahid_class, sizeof(luahid_t));
	luahid_t *hid = (luahid_t *)object->private;
	memset(hid, 0, sizeof(luahid_t));

	struct hid_driver *user_driver = &(hid->driver);
	user_driver->name = lunatik_checkalloc(L, NAME_MAX);
	lunatik_setstring(L, 1, user_driver, name, NAME_MAX);

	lunatik_checkfield(L, 1, "id_table", LUA_TTABLE);
	luaL_argcheck(L, (user_driver->id_table = luahid_setidtable(L, -1)) != NULL,
		      2, "invaild id_table");

	user_driver->probe = luahid_probe;
	user_driver->report_fixup = luahid_report_fixup;

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

