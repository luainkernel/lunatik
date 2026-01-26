#if defined(__arm__) && !defined(__aarch64__)
#include <stdint.h>
#include <stddef.h>
#include <linux/module.h>

extern uint64_t __udivmoddi4(uint64_t num, uint64_t den, uint64_t * rem);

typedef struct {
    int64_t quot;
    int64_t rem;
} int64_res_t;

int64_res_t __aeabi_ldivmod(int64_t num, int64_t den)
{
	int minus = 0;
	int64_t v;
	if (num < 0) {
		num = -num;
		minus = 1;
	}
	if (den < 0) {
		den = -den;
		minus ^= 1;
	}
	v = __udivmoddi4(num, den, NULL);
	if (minus)
		v = -v;
	return (int64_res_t){v, 0};
}
EXPORT_SYMBOL(__aeabi_ldivmod);

typedef struct {
    uint64_t quot;
    uint64_t rem;
} uint64_res_t;

uint64_res_t __aeabi_uldivmod(uint64_t num, uint64_t den)
{
    uint64_t rem, quot;
    quot = __udivmoddi4(num, den, &rem);
    return (uint64_res_t){quot, rem};
}
EXPORT_SYMBOL(__aeabi_uldivmod);
#endif
