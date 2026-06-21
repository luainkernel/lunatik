/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef _LUASET_H
#define _LUASET_H

#include <linux/string.h>

#include <lunatik.h>

#define LUASET_SEP	'.'

typedef struct luaset_s {
	size_t n;		/* number of members */
	const uint32_t *off;	/* n+1 offsets into blob */
	const char *blob;	/* sorted members concatenated, no separator */
	const uint32_t *flags;	/* NULL for a plain set; per-member flags when labeled */
} luaset_t;

LUNATIK_PRIVATECHECKER(luaset_check, luaset_t *);

static inline int luaset_keycmp(const char *a, uint32_t alen, const char *b, uint32_t blen)
{
	uint32_t m = min(alen, blen);
	int c = memcmp(a, b, m);
	return c != 0 ? c : (alen > blen) - (alen < blen);
}

static inline ssize_t luaset_find(const luaset_t *set, const char *s, uint32_t len)
{
	ssize_t lo = 0, hi = (ssize_t)set->n - 1;

	while (lo <= hi) {
		ssize_t mid = lo + (hi - lo) / 2;
		const char *member = set->blob + set->off[mid];
		uint32_t mlen = set->off[mid + 1] - set->off[mid];
		int c = luaset_keycmp(s, len, member, mlen);

		if (c == 0)
			return mid;
		if (c < 0)
			hi = mid - 1;
		else
			lo = mid + 1;
	}
	return -1;
}

/***
* Returns the number of members.
* @function __len
* @treturn integer the number of members.
*/
static inline int luaset_length(lua_State *L)
{
	luaset_t *set = luaset_check(L, 1);
	lua_pushinteger(L, (lua_Integer)set->n);
	return 1;
}

static inline void luaset_release(void *private)
{
	luaset_t *set = (luaset_t *)private;
	lunatik_free(set->blob);
	lunatik_free(set->off);
	lunatik_free(set->flags);
}

extern const lunatik_class_t luaset_class;
extern const lunatik_class_t luaset_labeled_class;
int luaset_new(lua_State *L);
int luaset_labeled(lua_State *L);

#endif /* _LUASET_H */

