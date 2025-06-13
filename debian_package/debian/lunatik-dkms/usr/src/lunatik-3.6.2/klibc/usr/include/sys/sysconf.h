/*
 * sys/sysconf.h
 *
 * sysconf() macros and demultiplex
 * This file is included in <unistd.h>
 *
 * Add things here as needed, we don't really want to add things wildly.
 * For things that require a lot of code, create an out-of-line function
 * and put it in a .c file in the sysconf directory.
 */

#ifndef _SYS_SYSCONF_H
#define _SYS_SYSCONF_H

#ifndef _UNISTD_H
# include <unistd.h>
#endif
#include <errno.h>

enum sysconf {
	_SC_PAGESIZE = 1,
};

__extern long sysconf(int);

__must_inline long __sysconf_inline(int __val)
{
	switch (__val) {
	case _SC_PAGESIZE:
		return getpagesize();
	default:
		errno = EINVAL;
		return -1;
	}
}

#define sysconf(x) \
	(__builtin_constant_p(x) ? __sysconf_inline(x) : sysconf(x))

#endif /* _SYS_SYSCONF_H */
