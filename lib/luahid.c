/*
* SPDX-FileCopyrightText: (c) 2025 Jieming Zhou <qrsikno@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/version.h>
#include <linux/slab.h>
#include <linux/limits.h>
#include <asm/byteorder.h>

#include <linux/hid.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

typedef struct luahid_s {
	lunatik_object_t *runtime;
	struct hid_driver driver;
} luahid_t;

/*
 * kernel codes copied & revised from drivers/hid/hid-generic.c
 * links: https://elixir.bootlin.com/linux/v6.13.7/source/drivers/hid/hid-generic.c 
 */
static int hid_probe(struct hid_device *hdev,
			     const struct hid_device_id *id)
{
	int ret;

	hdev->quirks |= HID_QUIRK_INPUT_PER_APP;

	ret = hid_parse(hdev);
	if (ret)
		return ret;

	return hid_hw_start(hdev, HID_CONNECT_DEFAULT);
}

static const struct hid_device_id hid_table[] = {
	{HID_DEVICE(HID_BUS_ANY, HID_GROUP_ANY, HID_ANY_ID, HID_ANY_ID)},
	{ }
};
MODULE_DEVICE_TABLE(hid, hid_table);

static void luahid_release(void *private)
{
	luahid_t *hid = (luahid_t *)private;
	if (hid) {
		hid_unregister_driver(&hid->driver);
		lunatik_putobject(hid->runtime);
	}
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

/*
 * Helper function to safely get an integer field from a Lua table.
 */
static lua_Integer get_int_field(lua_State *L, int table_idx, const char *field_name, lua_Integer default_val)
{
	lua_Integer result = default_val;
	if (lua_getfield(L, table_idx, field_name) == LUA_TNUMBER) {
		result = lua_tointeger(L, -1);
	}
	lua_pop(L, 1); /* pop the value or nil */
	return result;
}

/*
 * Parses the id_table from the Lua script.
 * Allocates a C array of hid_device_id structs.
 * Returns the default hid_table if no custom table is provided.
 */
static const struct hid_device_id *luahid_parse_id_table(lua_State *L, int idx)
{
	/* Check if the 'id_table' field exists and is a table */
	if (lua_getfield(L, idx, "id_table") != LUA_TTABLE) {
		lua_pop(L, 1); 
		return hid_table; 
	}

	size_t len = luaL_len(L, -1);
	if (len == 0) {
		lua_pop(L, 1); 
		return hid_table; 
	}

	struct hid_device_id *user_table = lunatik_checkalloc(L, sizeof(struct hid_device_id) * (len + 1));

	for (size_t i = 0; i < len; i++) {
		if (lua_geti(L, -1, i + 1) != LUA_TTABLE) {
			kfree(user_table);
			luaL_error(L, "id_table entry #%zu is not a table", i + 1);
			return NULL; /* Unreachable */
		}

		user_table[i].bus = get_int_field(L, -1, "bus", HID_BUS_ANY);
		user_table[i].group = get_int_field(L, -1, "group", HID_GROUP_ANY);
		user_table[i].vendor = get_int_field(L, -1, "vendor", HID_ANY_ID);
		user_table[i].product = get_int_field(L, -1, "product", HID_ANY_ID);
		user_table[i].driver_data = 0; /* driver_data not supported from Lua for simplicity */

		pr_warn("id_table[%zu] = { bus: %d, group: %d, vendor: 0x%04x, product: 0x%04x }\n",
		       i, user_table[i].bus, user_table[i].group,
		       user_table[i].vendor, user_table[i].product);

		lua_pop(L, 1); 
	}

	/* Add the null terminator entry */
	memset(&user_table[len], 0, sizeof(struct hid_device_id));

	lua_pop(L, 1); /* Pop the id_table itself */
	return user_table;
}

static int luahid_register(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE); /* assure that is a driver */

	lunatik_object_t *object = lunatik_newobject(L, &luahid_class, sizeof(luahid_t));
	luahid_t *hidvar = (luahid_t *)object->private;

	/*
	 * configure the driver's properties & callbacks
	 */
	struct hid_driver *user_driver = &(hidvar->driver);
	user_driver->name = lunatik_checkalloc(L, NAME_MAX);
	lunatik_setstring(L, 1, user_driver, name, NAME_MAX);
	user_driver->id_table = luahid_parse_id_table(L, 1);
	user_driver->match = NULL;
	user_driver->probe = hid_probe;

	lunatik_registerobject(L, 1, object);

	int ret = __hid_register_driver(user_driver, THIS_MODULE, KBUILD_MODNAME);
	if (ret) {
		lunatik_unregisterobject(L, object);
		luaL_error(L, "failed to register hid driver: %s", user_driver->name);
	} 
	lunatik_setruntime(L, hid, hidvar);
	lunatik_getobject(hidvar->runtime);
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
