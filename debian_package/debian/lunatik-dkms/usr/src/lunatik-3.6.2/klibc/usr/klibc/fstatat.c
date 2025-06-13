#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/syscall.h>

static void timespec_from_statx(struct timespec *ts,
				const struct statx_timestamp *xts)
{
	ts->tv_sec = xts->tv_sec;
	ts->tv_nsec = xts->tv_nsec;
}

int fstatat(int dirfd, const char *path, struct stat *buf, int flags)
{
	struct statx xbuf;

	if (statx(dirfd, path, flags | AT_NO_AUTOMOUNT, STATX_BASIC_STATS,
		  &xbuf))
		return -1;

	buf->st_dev = makedev(xbuf.stx_dev_major, xbuf.stx_dev_minor);
	buf->st_ino = xbuf.stx_ino;
	buf->st_nlink = xbuf.stx_nlink;
	buf->st_mode = xbuf.stx_mode;
	buf->st_uid = xbuf.stx_uid;
	buf->st_gid = xbuf.stx_gid;
	buf->st_rdev = makedev(xbuf.stx_rdev_major, xbuf.stx_rdev_minor);
	buf->st_size = xbuf.stx_size;
	buf->st_blksize = xbuf.stx_blksize;
	buf->st_blocks = xbuf.stx_blocks;
	timespec_from_statx(&buf->st_atim, &xbuf.stx_atime);
	timespec_from_statx(&buf->st_ctim, &xbuf.stx_ctime);
	timespec_from_statx(&buf->st_mtim, &xbuf.stx_mtime);
	return 0;
}
