/*
 * sys/stat.h
 */

#ifndef _SYS_STAT_H
#define _SYS_STAT_H

#include <klibc/extern.h>
#include <sys/types.h>
#include <sys/time.h>		/* For struct timespec */
#include <linux/stat.h>

/* 2.6.21 kernels have once again hidden a bunch of stuff... */
#ifndef S_IFMT

#define S_IFMT  00170000
#define S_IFSOCK 0140000
#define S_IFLNK	 0120000
#define S_IFREG  0100000
#define S_IFBLK  0060000
#define S_IFDIR  0040000
#define S_IFCHR  0020000
#define S_IFIFO  0010000
#define S_ISUID  0004000
#define S_ISGID  0002000
#define S_ISVTX  0001000

#define S_ISLNK(m)	(((m) & S_IFMT) == S_IFLNK)
#define S_ISREG(m)	(((m) & S_IFMT) == S_IFREG)
#define S_ISDIR(m)	(((m) & S_IFMT) == S_IFDIR)
#define S_ISCHR(m)	(((m) & S_IFMT) == S_IFCHR)
#define S_ISBLK(m)	(((m) & S_IFMT) == S_IFBLK)
#define S_ISFIFO(m)	(((m) & S_IFMT) == S_IFIFO)
#define S_ISSOCK(m)	(((m) & S_IFMT) == S_IFSOCK)

#define S_IRWXU 00700
#define S_IRUSR 00400
#define S_IWUSR 00200
#define S_IXUSR 00100

#define S_IRWXG 00070
#define S_IRGRP 00040
#define S_IWGRP 00020
#define S_IXGRP 00010

#define S_IRWXO 00007
#define S_IROTH 00004
#define S_IWOTH 00002
#define S_IXOTH 00001

#endif

#define S_IRWXUGO	(S_IRWXU|S_IRWXG|S_IRWXO)
#define S_IALLUGO	(S_ISUID|S_ISGID|S_ISVTX|S_IRWXUGO)
#define S_IRUGO		(S_IRUSR|S_IRGRP|S_IROTH)
#define S_IWUGO		(S_IWUSR|S_IWGRP|S_IWOTH)
#define S_IXUGO		(S_IXUSR|S_IXGRP|S_IXOTH)

/* struct stat with 64-bit time, not used by kernel UAPI */
struct stat {
        dev_t		st_dev;
        ino_t		st_ino;
        mode_t		st_mode;
        unsigned int	st_nlink;
        uid_t		st_uid;
        gid_t		st_gid;
        dev_t		st_rdev;
        off_t		st_size;
        int		st_blksize;
        off_t		st_blocks;
        struct timespec	st_atim;
        struct timespec	st_mtim;
        struct timespec	st_ctim;
};
#define st_atime	st_atim.tv_sec
#define st_mtime	st_mtim.tv_sec
#define st_ctime	st_ctim.tv_sec

__extern int stat(const char *, struct stat *);
__extern int fstat(int, struct stat *);
__extern int fstatat(int, const char *, struct stat *, int);
__extern int lstat(const char *, struct stat *);
__extern int statx(int, const char *, int, unsigned int, struct statx *);
__extern mode_t umask(mode_t);
__extern int mknod(const char *, mode_t, dev_t);
__extern int mknodat(int, const char *, mode_t, dev_t);
__extern int mkfifo(const char *, mode_t);
__extern int utimensat(int, const char *, const struct timespec *, int);
__extern int fchmodat(int, const char *, mode_t, int);

__extern_inline int mkfifo(const char *__p, mode_t __m)
{
	return mknod(__p, (__m & ~S_IFMT) | S_IFIFO, (dev_t) 0);
}

#endif				/* _SYS_STAT_H */
