/*
 * sys/ioctl.h
 */

#ifndef _SYS_IOCTL_H
#define _SYS_IOCTL_H

#include <sys/types.h>
#include <klibc/extern.h>
#include <linux/ioctl.h>
#include <asm/ioctls.h>

/* the SIOCxxx I/O are hidden */
#include <linux/sockios.h>

__extern int ioctl(int, int, void *);

#endif				/* _SYS_IOCTL_H */
