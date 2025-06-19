/*
 * poll.h
 */

#ifndef _POLL_H
#define _POLL_H

#include <klibc/extern.h>
#include <sys/time.h>
#include <signal.h>
#include <linux/poll.h>

/* POSIX specifies "int" for the timeout, Linux seems to use long... */

typedef unsigned int nfds_t;
__extern int poll(struct pollfd *, nfds_t, long);
__extern int ppoll(struct pollfd *, nfds_t, struct timespec *,
		   const sigset_t *);

#endif				/* _POLL_H */
