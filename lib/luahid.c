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
 * kernel codes copied from drivers/hid/hid-generic.c
 * links: https://elixir.bootlin.com/linux/v6.13.7/source/drivers/hid/hid-generic.c 
 */
static int hid_generic_probe(struct hid_device *hdev,
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

/*
 * This function is called when matching a hid driver
 * A function to merge user-defined match's logic with the kernel's
 */
static bool hid_match(struct hid_device *hdev,
			      bool ignore_special_driver) {
	/* 
	 * this is a device need to be ignored and processed by the
	 * generic driver
	 */
	if (ignore_special_driver)
		return false;

	return hid_match_id(hdev, hid_table);
}


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


static int luahid_register(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE); /* assure that is a driver */

	lunatik_object_t *object = lunatik_newobject(L, &luahid_class, sizeof(luahid_t));
	luahid_t *hid = (luahid_t *)object->private;

	/*
	 * configure the driver's properties & callbacks
	 */
	struct hid_driver *user_driver = &(hid->driver);
	user_driver->name = lunatik_checkalloc(L, NAME_MAX);
	lunatik_setstring(L, 1, user_driver, name, NAME_MAX);
	user_driver->id_table = hid_table;
	user_driver->match = hid_match;
	user_driver->probe = hid_generic_probe;

	lunatik_registerobject(L, 1, object);

	int ret = __hid_register_driver(user_driver, THIS_MODULE, KBUILD_MODNAME);
	if (ret) {
		lunatik_unregisterobject(L, object);
		luaL_error(L, "failed to register hid driver: %s", user_driver->name);
	} 
	lunatik_setruntime(L, hid, hid);
	lunatik_getobject(hid->runtime);
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
