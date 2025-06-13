/*
* SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luaxtable_h
#define luaxtable_h

#define LUAXTABLE_USERDATA_SIZE 256

struct luaxtable_s;

typedef struct luaxtable_info_s {
	char userargs[LUAXTABLE_USERDATA_SIZE];

	/* used internally by the luaxtable kernel module */
	struct luaxtable_s *data __attribute__((aligned(8)));
} luaxtable_info_t;

#endif

