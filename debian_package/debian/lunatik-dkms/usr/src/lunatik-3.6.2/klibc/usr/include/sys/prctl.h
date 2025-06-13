#ifndef _SYS_PRCTL_H
#define _SYS_PRCTL_H

#include <sys/types.h>
#include <klibc/extern.h>
#include <linux/prctl.h>

/* glibc has this as a varadic function, so join the club... */
__extern int prctl(int, ...);

#endif /* _SYS_PRCTL_H */
