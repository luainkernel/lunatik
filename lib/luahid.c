/*
* SPDX-FileCopyrightText: (c) 2025 Jieming Zhou <qrsikno@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <string.h>
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/hid.h>
#include <lunatik.h>
#include <lauxlib.h>

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
	luaL_argcheck(L, (user_driver->id_table = luahid_setidtable(L, -1)) == NULL,
			   2, "id_table is not specified or invalid");

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

