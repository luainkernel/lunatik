/*
 * sys/resource.h
 */

#ifndef _SYS_RESOURCE_H
#define _SYS_RESOURCE_H

#include <klibc/extern.h>
#include <sys/types.h>
#include <sys/time.h>

#define RUSAGE_SELF	0
#define RUSAGE_CHILDREN	(-1)
#define RUSAGE_BOTH	(-2)
#define RUSAGE_THREAD	1

struct	rusage {
	struct timeval_old ru_utime;	/* user time used */
	struct timeval_old ru_stime;	/* system time used */
	__kernel_long_t	ru_maxrss;	/* maximum resident set size */
	__kernel_long_t	ru_ixrss;	/* integral shared memory size */
	__kernel_long_t	ru_idrss;	/* integral unshared data size */
	__kernel_long_t	ru_isrss;	/* integral unshared stack size */
	__kernel_long_t	ru_minflt;	/* page reclaims */
	__kernel_long_t	ru_majflt;	/* page faults */
	__kernel_long_t	ru_nswap;	/* swaps */
	__kernel_long_t	ru_inblock;	/* block input operations */
	__kernel_long_t	ru_oublock;	/* block output operations */
	__kernel_long_t	ru_msgsnd;	/* messages sent */
	__kernel_long_t	ru_msgrcv;	/* messages received */
	__kernel_long_t	ru_nsignals;	/* signals received */
	__kernel_long_t	ru_nvcsw;	/* voluntary context switches */
	__kernel_long_t	ru_nivcsw;	/* involuntary " */
};

#define PRIO_MIN	(-20)
#define PRIO_MAX	20

#define PRIO_PROCESS	0
#define PRIO_PGRP	1
#define PRIO_USER	2

__extern int getpriority(int, int);
__extern int setpriority(int, int, int);

__extern int getrusage(int, struct rusage *);

#endif				/* _SYS_RESOURCE_H */
