#include <errno.h>
#include <sys/poll.h>
#include <sys/syscall.h>

#ifndef __NR_poll

int poll(struct pollfd *fds, nfds_t nfds, long timeout)
{
	struct timespec timeout_ts;
	struct timespec *timeout_ts_p = NULL;

	if (timeout >= 0) {
		timeout_ts.tv_sec = timeout / 1000;
		timeout_ts.tv_nsec = (timeout % 1000) * 1000000;
		timeout_ts_p = &timeout_ts;
	}

	return ppoll(fds, nfds, timeout_ts_p, 0);
}

#endif /* __NR_poll */
