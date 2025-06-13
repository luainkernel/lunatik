/*
 * isatty.c
 */

#include <unistd.h>
#include <termios.h>
#include <errno.h>

int isatty(int fd)
{
	struct termios dummy;

	/* All ttys support TIOCGPGRP */
	/* except /dev/console which needs TCGETS */
	return !ioctl(fd, TCGETS, &dummy);
}
