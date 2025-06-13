/*
 * sys/time.h
 */

#ifndef _SYS_TIME_H
#define _SYS_TIME_H

#include <klibc/extern.h>
#include <klibc/endian.h>
#include <stddef.h>
#include <sys/types.h>

/* struct timespec as used by current kernel UAPI (time64 on 32-bit) */
struct timespec {
	__kernel_time64_t	tv_sec;
#if __BYTE_ORDER == __BIG_ENDIAN && __BITS_PER_LONG == 32
	int			:32;
#endif
	long			tv_nsec;
#if __BYTE_ORDER == __LITTLE_ENDIAN && __BITS_PER_LONG == 32
	int			:32;
#endif
};

/* struct timeval with 64-bit time, not used by kernel UAPI */
struct timeval {
	__kernel_time64_t	tv_sec;
	__kernel_suseconds_t	tv_usec;
};

/* struct timeval as used by old kernel UAPI */
struct timeval_old {
	__kernel_time_t		tv_sec;
	__kernel_suseconds_t	tv_usec;
};

struct itimerspec {
	struct timespec	it_interval;
	struct timespec it_value;
};

struct itimerval {
	struct timeval_old	it_interval;
	struct timeval_old	it_value;
};

struct timezone {
	int	tz_minuteswest;
	int	tz_dsttime;
};

#define ITIMER_REAL		0
#define ITIMER_VIRTUAL		1
#define ITIMER_PROF		2

#define CLOCK_REALTIME			0
#define CLOCK_MONOTONIC			1
#define CLOCK_PROCESS_CPUTIME_ID	2
#define CLOCK_THREAD_CPUTIME_ID		3
#define CLOCK_MONOTONIC_RAW		4
#define CLOCK_REALTIME_COARSE		5
#define CLOCK_MONOTONIC_COARSE		6
#define CLOCK_BOOTTIME			7
#define CLOCK_REALTIME_ALARM		8
#define CLOCK_BOOTTIME_ALARM		9
#define CLOCK_TAI			11

#define TIMER_ABSTIME			0x01

/* The 2.6.20 Linux headers always #define FD_ZERO __FD_ZERO, etc, in
   <linux/time.h> but not all architectures define the
   double-underscore ones, except __NFDBITS, __FD_SETSIZE and
   __FDSET_LONGS which are defined in <linux/posix_types.h>.

   Unfortunately, some architectures define the double-underscore ones
   as inlines, so we can't use a simple #ifdef test.  Thus, the only
   safe option remaining is to #undef the top-level macros. */

#undef FD_ZERO
#undef FD_SET
#undef FD_CLR
#undef FD_ISSET
#undef FD_SETSIZE

__extern void *memset(void *, int, size_t);
static inline void FD_ZERO(fd_set *__fdsetp)
{
	memset(__fdsetp, 0, sizeof(fd_set));
}
static inline void FD_SET(int __fd, fd_set *__fdsetp)
{
	__fdsetp->fds_bits[__fd/BITS_PER_LONG] |=
		(1UL << (__fd % BITS_PER_LONG));
}
static inline void FD_CLR(int __fd, fd_set *__fdsetp)
{
	__fdsetp->fds_bits[__fd/BITS_PER_LONG] &=
		~(1UL << (__fd % BITS_PER_LONG));
}
static inline int FD_ISSET(int __fd, fd_set *__fdsetp)
{
	return (__fdsetp->fds_bits[__fd/BITS_PER_LONG] >>
		(__fd % BITS_PER_LONG)) & 1;
}

#define FD_SETSIZE __FD_SETSIZE

__extern int gettimeofday(struct timeval *, struct timezone *);
__extern int settimeofday(const struct timeval *, const struct timezone *);
__extern int clock_gettime(clockid_t, struct timespec *);
__extern int clock_settime(clockid_t, const struct timespec *);
__extern int clock_nanosleep(clockid_t, int, const struct timespec *, struct timespec *);
__extern int getitimer(int, struct itimerval *);
__extern int setitimer(int, const struct itimerval *, struct itimerval *);
__extern int utimes(const char *, const struct timeval[2]);

#endif				/* _SYS_TIME_H */
