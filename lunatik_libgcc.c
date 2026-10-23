/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <stdint.h>

/* GCC folds a / and a % of the same operands into this call, so it is spelled with neither */
int64_t __divmoddi4(int64_t num, int64_t den, int64_t *rem)
{
	int64_t quot = __divdi3(num, den);

	*rem = num - quot * den;
	return quot;
}

