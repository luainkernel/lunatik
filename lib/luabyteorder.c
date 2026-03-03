/*
* SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/module.h>
#include <linux/byteorder/generic.h>

#include <lunatik.h>

/***
* Byte Order Conversion
* @module byteorder
*/
#define LUABYTEORDER_BYTESWAPPER(swapper, T)		\
static int luabyteorder_##swapper(lua_State *L)		\
{							\
	T x = (T)luaL_checkinteger(L, 1);		\
	lua_pushinteger(L, (lua_Integer)swapper(x));	\
	return 1;					\
}

/***
* Converts a 16-bit integer from host byte order to big-endian byte order.
* @function htobe16
* @tparam integer num The 16-bit integer in host byte order.
* @treturn integer The integer in big-endian byte order.
*/
LUABYTEORDER_BYTESWAPPER(cpu_to_be16, u16);

/***
* Converts a 32-bit integer from host byte order to big-endian byte order.
* @function htobe32
* @tparam integer num The 32-bit integer in host byte order.
* @treturn integer The integer in big-endian byte order.
*/
LUABYTEORDER_BYTESWAPPER(cpu_to_be32, u32);

/***
* Converts a 16-bit integer from host byte order to little-endian byte order.
* @function htole16
* @tparam integer num The 16-bit integer in host byte order.
* @treturn integer The integer in little-endian byte order.
*/
LUABYTEORDER_BYTESWAPPER(cpu_to_le16, u16);

/***
* Converts a 32-bit integer from host byte order to little-endian byte order.
* @function htole32
* @tparam integer num The 32-bit integer in host byte order.
* @treturn integer The integer in little-endian byte order.
*/
LUABYTEORDER_BYTESWAPPER(cpu_to_le32, u32);

/***
* Converts a 16-bit integer from big-endian byte order to host byte order.
* @function be16toh
* @tparam integer num The 16-bit integer in big-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUABYTEORDER_BYTESWAPPER(be16_to_cpu, u16);

/***
* Converts a 32-bit integer from big-endian byte order to host byte order.
* @function be32toh
* @tparam integer num The 32-bit integer in big-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUABYTEORDER_BYTESWAPPER(be32_to_cpu, u32);

/***
* Converts a 16-bit integer from little-endian byte order to host byte order.
* @function le16toh
* @tparam integer num The 16-bit integer in little-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUABYTEORDER_BYTESWAPPER(le16_to_cpu, u16);

/***
* Converts a 32-bit integer from little-endian byte order to host byte order.
* @function le32toh
* @tparam integer num The 32-bit integer in little-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUABYTEORDER_BYTESWAPPER(le32_to_cpu, u32);

/***
* Converts a 64-bit integer from host byte order to big-endian byte order.
* @function htobe64
* @tparam integer num The 64-bit integer in host byte order.
* @treturn integer The integer in big-endian byte order.
*/
LUABYTEORDER_BYTESWAPPER(cpu_to_be64, u64);

/***
* Converts a 64-bit integer from host byte order to little-endian byte order.
* @function htole64
* @tparam integer num The 64-bit integer in host byte order.
* @treturn integer The integer in little-endian byte order.
*/
LUABYTEORDER_BYTESWAPPER(cpu_to_le64, u64);

/***
* Converts a 64-bit integer from big-endian byte order to host byte order.
* @function be64toh
* @tparam integer num The 64-bit integer in big-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUABYTEORDER_BYTESWAPPER(be64_to_cpu, u64);

/***
* Converts a 64-bit integer from little-endian byte order to host byte order.
* @function le64toh
* @tparam integer num The 64-bit integer in little-endian byte order.
* @treturn integer The integer in host byte order.
*/
LUABYTEORDER_BYTESWAPPER(le64_to_cpu, u64);

static const luaL_Reg luabyteorder_lib[] = {
/***
* Converts a 16-bit integer from network (big-endian) byte order to host byte order.
* @function ntoh16
* @tparam integer num The 16-bit integer in network byte order.
* @treturn integer The integer in host byte order.
*/
	{"ntoh16", luabyteorder_be16_to_cpu},
/***
* Converts a 32-bit integer from network (big-endian) byte order to host byte order.
* @function ntoh32
* @tparam integer num The 32-bit integer in network byte order.
* @treturn integer The integer in host byte order.
*/
	{"ntoh32", luabyteorder_be32_to_cpu},
/***
* Converts a 16-bit integer from host byte order to network (big-endian) byte order.
* @function hton16
* @tparam integer num The 16-bit integer in host byte order.
* @treturn integer The integer in network byte order.
*/
	{"hton16", luabyteorder_cpu_to_be16},
/***
* Converts a 32-bit integer from host byte order to network (big-endian) byte order.
* @function hton32
* @tparam integer num The 32-bit integer in host byte order.
* @treturn integer The integer in network byte order.
*/
	{"hton32", luabyteorder_cpu_to_be32},
	{"htobe16", luabyteorder_cpu_to_be16},
	{"htobe32", luabyteorder_cpu_to_be32},
	{"htole16", luabyteorder_cpu_to_le16},
	{"htole32", luabyteorder_cpu_to_le32},
	{"be16toh", luabyteorder_be16_to_cpu},
	{"be32toh", luabyteorder_be32_to_cpu},
	{"le16toh", luabyteorder_le16_to_cpu},
	{"le32toh", luabyteorder_le32_to_cpu},
/***
* Converts a 64-bit integer from network (big-endian) byte order to host byte order.
* @function ntoh64
* @tparam integer num The 64-bit integer in network byte order.
* @treturn integer The integer in host byte order.
*/
	{"ntoh64", luabyteorder_be64_to_cpu},
/***
* Converts a 64-bit integer from host byte order to network (big-endian) byte order.
* @function hton64
* @tparam integer num The 64-bit integer in host byte order.
* @treturn integer The integer in network byte order.
*/
	{"hton64", luabyteorder_cpu_to_be64},
	{"htobe64", luabyteorder_cpu_to_be64},
	{"htole64", luabyteorder_cpu_to_le64},
	{"be64toh", luabyteorder_be64_to_cpu},
	{"le64toh", luabyteorder_le64_to_cpu},
	{NULL, NULL}
};

LUNATIK_NEWLIB(byteorder, luabyteorder_lib, NULL, NULL);

static int __init luabyteorder_init(void)
{
	return 0;
}

static void __exit luabyteorder_exit(void)
{
}

module_init(luabyteorder_init);
module_exit(luabyteorder_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>");

