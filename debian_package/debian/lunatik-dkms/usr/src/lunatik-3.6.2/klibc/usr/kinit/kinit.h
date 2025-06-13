/*
 * kinit/kinit.h
 */

#ifndef KINIT_H
#define KINIT_H

#include <stddef.h>
#include <stdio.h>
#include <sys/types.h>

int do_mounts(int argc, char *argv[]);
int mount_nfs_root(int argc, char *argv[], int flags);
int ramdisk_load(int argc, char *argv[]);
void md_run(int argc, char *argv[]);
const char *bdevname(dev_t dev);

extern int mnt_procfs;
extern int mnt_sysfs;

extern int init_argc;
extern char **init_argv;
extern const char *progname;

char *get_arg(int argc, char *argv[], const char *name);
int get_flag(int argc, char *argv[], const char *name);

int getintfile(const char *path, long *val);

ssize_t readfile(const char *path, char **pptr);
ssize_t freadfile(FILE *f, char **pptr);

/*
 * min()/max() macros that also do
 * strict type-checking.. See the
 * "unnecessary" pointer comparison.
 * From the Linux kernel.
 */
#define min(x, y) ({ \
	typeof(x) _x = (x);     \
	typeof(y) _y = (y);     \
	(void) (&_x == &_y);            \
	_x < _y ? _x : _y; })

#define max(x, y) ({ \
	typeof(x) _x = (x);     \
	typeof(y) _y = (y);     \
	(void) (&_x == &_y);            \
	_x > _y ? _x : _y; })


#ifdef DEBUG
# define dprintf printf
#else
# define dprintf(...) ((void)0)
#endif

#ifdef DEBUG
void dump_args(int argc, char *argv[]);
#else
static inline void dump_args(int argc, char *argv[])
{
	(void)argc;
	(void)argv;
}
#endif

int drop_capabilities(const char *caps);

#endif				/* KINIT_H */
