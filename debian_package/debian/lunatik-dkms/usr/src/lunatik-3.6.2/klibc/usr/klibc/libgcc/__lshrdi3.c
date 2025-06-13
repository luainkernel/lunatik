/*
 * libgcc/__lshrdi3.c
 */

#include <stdint.h>
#include <stddef.h>

uint64_t __lshrdi3(uint64_t v, int cnt)
{
	int c = cnt & 31;
	uint32_t vl = (uint32_t) v;
	uint32_t vh = (uint32_t) (v >> 32);

	if (cnt & 32) {
		vl = (vh >> c);
		vh = 0;
	} else {
		vl = (vl >> c) + (vh << (32 - c));
		vh = (vh >> c);
	}

	return ((uint64_t) vh << 32) + vl;
}
