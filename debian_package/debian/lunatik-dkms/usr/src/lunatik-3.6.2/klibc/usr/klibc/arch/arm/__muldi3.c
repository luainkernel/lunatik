#include <stdint.h>

uint64_t __muldi3(uint64_t a, uint64_t b)
{
	uint32_t al = (uint32_t)a;
	uint32_t ah = (uint32_t)(a >> 32);
	uint32_t bl = (uint32_t)b;
	uint32_t bh = (uint32_t)(b >> 32);
	uint64_t v;

	v = (uint64_t)al * bl;
	v += (uint64_t)(al*bh+ah*bl) << 32;

	return v;
}
