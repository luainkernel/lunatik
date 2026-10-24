/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/export.h>

#include <stdint.h>

/* GCC folds a / and a % of the same operands into this call, so it is spelled with neither */
int64_t __divmoddi4(int64_t num, int64_t den, int64_t *rem)
{
	int64_t quot = __divdi3(num, den);

	*rem = num - quot * den;
	return quot;
}
EXPORT_SYMBOL(__divmoddi4);

/* Kbuild defines these for the helpers it links from klibc, the ones the kernel does not export */
#ifdef LUNATIK_LIBGCC_udivmoddi4
EXPORT_SYMBOL(__udivmoddi4);
#endif
#ifdef LUNATIK_LIBGCC_divdi3
EXPORT_SYMBOL(__divdi3);
#endif
#ifdef LUNATIK_LIBGCC_udivdi3
EXPORT_SYMBOL(__udivdi3);
#endif
#ifdef LUNATIK_LIBGCC_moddi3
/* klibc's gives the remainder the quotient's sign, where luaV_mod corrects from C's, the dividend's */
int64_t __moddi3(int64_t num, int64_t den)
{
	return num - __divdi3(num, den) * den;
}
EXPORT_SYMBOL(__moddi3);
#endif
#ifdef LUNATIK_LIBGCC_umoddi3
EXPORT_SYMBOL(__umoddi3);
#endif

