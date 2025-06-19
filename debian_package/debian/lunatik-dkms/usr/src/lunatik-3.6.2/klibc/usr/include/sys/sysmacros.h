/*
 * sys/sysmacros.h
 *
 * Constructs to create and pick apart dev_t.  The double-underscore
 * versions are macros so they can be used as constants.
 */

#ifndef _SYS_SYSMACROS_H
#define _SYS_SYSMACROS_H

#include <klibc/compiler.h>
#include <sys/types.h>

#define __major(__d) ((int)(((__d) >> 8) & 0xfffU))
__static_inline int _major(dev_t __d)
{
	return __major(__d);
}
#define major(__d) _major(__d)

#define __minor(__d) ((int)(((__d) & 0xffU)|(((__d) >> 12) & 0xfff00U)))
__static_inline int _minor(dev_t __d)
{
	return __minor(__d);
}
#define minor(__d) _minor(__d)

#define __makedev(__ma, __mi) \
	((dev_t)((((__ma) & 0xfffU) << 8)| \
		 ((__mi) & 0xffU)|(((__mi) & 0xfff00U) << 12)))
__static_inline dev_t _makedev(int __ma, int __mi)
{
	return __makedev(__ma, __mi);
}
#define makedev(__ma, __mi) _makedev(__ma, __mi)

#endif				/* _SYS_SYSMACROS_H */
