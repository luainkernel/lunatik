/*
 * sys/select.h
 */

#ifndef _SYS_SELECT_H
#define _SYS_SELECT_H

#include <klibc/extern.h>
#include <sys/time.h>
#include <sys/types.h>
#include <signal.h>

__extern int select(int, fd_set *, fd_set *, fd_set *, struct timeval *);
__extern int pselect(int, fd_set *, fd_set *, fd_set *,
		     const struct timespec *, const sigset_t *);

#endif				/* _SYS_SELECT_H */
