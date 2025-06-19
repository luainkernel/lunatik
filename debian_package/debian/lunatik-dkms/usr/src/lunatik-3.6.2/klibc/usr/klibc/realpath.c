#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <unistd.h>

/*
 * Note that this requires name to refer to an existing file.  This is
 * correct according to POSIX.  However, BSD and GNU implementations
 * also allow name to refer to a non-existing file in an existing
 * directory.
 */

char *realpath(const char *name, char *resolved_name)
{
	static const char proc_fd_prefix[] = "/proc/self/fd/";
	char proc_fd_name[sizeof(proc_fd_prefix) + sizeof(int) * 3];
	int allocated = 0;
	int fd;
	ssize_t len;

	/* Open for path lookup only */
	fd = open(name, O_PATH);
	if (fd < 0)
		return NULL;

	if (!resolved_name) {
		resolved_name = malloc(PATH_MAX);
		if (!resolved_name)
			goto out_close;
		allocated = 1;
	}

	/* Use procfs to read back the resolved name */
	sprintf(proc_fd_name, "%s%d", proc_fd_prefix, fd);
	len = readlink(proc_fd_name, resolved_name, PATH_MAX - 1);
	if (len < 0) {
		if (allocated)
			free(resolved_name);
		resolved_name = NULL;
	} else {
		resolved_name[len] = 0;
	}

out_close:
	close(fd);
	return resolved_name;
}
