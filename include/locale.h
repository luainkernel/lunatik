/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_locale_h
#define lunatik_locale_h

struct lconv { char *decimal_point; };
static inline struct lconv *localeconv(void)
{
	static struct lconv lc = { "." };
	return &lc;
}

#endif

