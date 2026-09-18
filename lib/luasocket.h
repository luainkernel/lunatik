/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luasocket_h
#define luasocket_h

#include <lunatik.h>

/* sock_alloc_file sleeps, so the caller has to be somewhere that can */
/* what comes back holds a file reference, the caller's to drop with fput */
struct socket *luasocket_openfile(lua_State *L, int ix);

#endif

