#ifndef _SYS_AUXV_H
#define _SYS_AUXV_H

#include <klibc/compiler.h>
#include <klibc/extern.h>
#include <elf.h>

#define _AUXVAL_MAX	AT_SYSINFO_EHDR

__extern unsigned long __auxval[_AUXVAL_MAX];

__static_inline unsigned long getauxval(unsigned long __t)
{
	return (__t >= _AUXVAL_MAX) ? 0 : __auxval[__t];
}

#endif /* _SYS_AUXV_H */
