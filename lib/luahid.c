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
#include <string.h>
#include <linux/hid.h>
#include <lunatik.h>
#include <lauxlib.h>

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
	{NULL, NULL}
};

static const luaL_Reg luahid_mt[] = {
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
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
*	 hid.register(hid_driver)
*/
static int luahid_register(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);

	lunatik_object_t *object = lunatik_newobject(L, &luahid_class, sizeof(luahid_t));
	luahid_t *hid = (luahid_t *)object->private;
	memset(hid, 0, sizeof(luahid_t));

	struct hid_driver *user_driver = &(hid->driver);
	user_driver->name = lunatik_checkalloc(L, NAME_MAX);
	lunatik_setstring(L, 1, user_driver, name, NAME_MAX);

	lunatik_checkfield(L, 1, "id_table", LUA_TTABLE);
	luaL_argcheck(L, (user_driver->id_table = luahid_setidtable(L, -1)) != NULL,
			   2, "invaild id_table");

	lunatik_setruntime(L, hid, hid);
	lunatik_getobject(hid->runtime);

	if (__hid_register_driver(user_driver, THIS_MODULE, KBUILD_MODNAME) != 0)
		luaL_error(L, "failed to register hid driver: %s", user_driver->name);

	hid->registered = true;
	lunatik_registerobject(L, 1, object);
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

