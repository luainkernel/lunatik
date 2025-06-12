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
#include "luadata.h"

typedef struct luahid_s {
	lunatik_object_t *runtime;
	struct hid_driver driver;
	lunatik_object_t *fixed_report_descriptor;
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

static void luahid_push_device_info_table(lua_State *L, struct hid_device *hdev)
{
    lua_newtable(L);

    lua_pushinteger(L, hdev->bus);
    lua_setfield(L, -2, "bus"); 

    lua_pushinteger(L, hdev->group);
    lua_setfield(L, -2, "group");

    lua_pushinteger(L, hdev->vendor);
    lua_setfield(L, -2, "vendor");

    lua_pushinteger(L, hdev->product);
    lua_setfield(L, -2, "product");

    lua_pushinteger(L, hdev->version);
    lua_setfield(L, -2, "version");

    lua_pushstring(L, hdev->name);
    lua_setfield(L, -2, "name");
}

static int luahid_report_fixup_handler(lua_State *L, luahid_t *hidvar, 
									   struct hid_device *hdev, __u8 *buf, unsigned int *size, 
									   __u8* ret_ptr) { 
	int ret = -1;

	if (lunatik_getregistry(L, hidvar) != LUA_TTABLE) {
		pr_err("luahid: could not find ops table for hid device\n");
		goto err;
	}

	if(lua_getfield(L, -1, "report_fixup") != LUA_TFUNCTION) {
		pr_err("luahid: report_fixup operation not defined\n");
		goto err;
	}

	if (hidvar->fixed_report_descriptor != NULL) {
		/* manually recircle the fixed report descriptor */
		lunatik_putobject(hidvar->fixed_report_descriptor);
		hidvar->fixed_report_descriptor = NULL;
	} 

	luahid_push_device_info_table(L, hdev);
	lunatik_object_t *original_data = luadata_new(buf, *size, hidvar->runtime->sleep, LUADATA_OPT_READONLY);
    if (!original_data) {
		pr_err("luahid: failed to create luadata for original report\n");
		goto err;
    }
    lunatik_pushobject(L, original_data); 

    if (lua_pcall(L, 2, 1, 0) != LUA_OK) {
        pr_err("luahid: error calling 'report_fixup': %s\n", lua_tostring(L, -1));
		goto err;
    }

	if (!lua_isnil(L, -1)) {
        lunatik_object_t* returned_object = lunatik_checkobject(L, -1);
        lunatik_getobject(returned_object);
		hidvar->fixed_report_descriptor = returned_object;

		luadata_t *data = (luadata_t *)returned_object->private;
		*size= data->size;
		ret_ptr = data->ptr;
	}

	return 0;
err: 
	return ret;
}

static const __u8* luahid_report_fixup(struct hid_device *hdev, __u8* buf, unsigned int *size) {
	struct hid_driver *driver = hdev->driver;
	luahid_t *hidvar = container_of(driver, luahid_t, driver);
	__u8* ret_ptr = buf;
	int ret;

	if (!driver || !driver->report_fixup || !hidvar->runtime) {
		pr_warn("No report_fixup callback defined for driver %s\n", driver ? driver->name : "unknown");
		return buf; /* No fixup needed */
	}

	lunatik_run(hidvar->runtime, luahid_report_fixup_handler, ret, hidvar, hdev, buf, size, ret_ptr);

	/* if error occured, returns the original buffer */
	if (ret) 
		return buf;
	else 
		return ret_ptr;
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
	user_driver->report_fixup = luahid_report_fixup;

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
