/*
 * stddef.h
 */

#ifndef _STDDEF_H
#define _STDDEF_H

#ifndef __KLIBC__
# error "__KLIBC__ not defined, compiler invocation error!"
#endif

/*
 * __SIZE_TYPE__ and __PTRDIFF_TYPE__ are defined by GCC and
 * many other compilers to what types the ABI expects on the
 * target platform for size_t and ptrdiff_t, so we use these
 * for size_t, ssize_t, ptrdiff_t definitions, if available;
 * fall back to unsigned long, which is correct on ILP32 and
 * LP64 platforms (Linux does not have any others) otherwise.
 *
 * Note: the order "long unsigned int" precisely matches GCC.
 */
#ifndef __SIZE_TYPE__
#define __SIZE_TYPE__ long unsigned int
#endif

#ifndef __PTRDIFF_TYPE__
#define __PTRDIFF_TYPE__ long int
#endif

#define _SIZE_T
typedef __SIZE_TYPE__ size_t;

#define _PTRDIFF_T
typedef __PTRDIFF_TYPE__ ptrdiff_t;

#undef NULL
#ifdef __cplusplus
# define NULL 0
#else
# define NULL ((void *)0)
#endif

#undef offsetof
#define offsetof(t,m) ((size_t)&((t *)0)->m)

/*
 * The container_of construct: if p is a pointer to member m of
 * container class c, then return a pointer to the container of which
 * *p is a member.
 */
#undef container_of
#define container_of(p, c, m) ((c *)((char *)(p) - offsetof(c,m)))

#endif				/* _STDDEF_H */
