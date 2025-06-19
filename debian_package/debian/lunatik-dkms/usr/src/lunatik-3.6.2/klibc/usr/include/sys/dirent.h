/*
 * sys/dirent.h
 */

#ifndef _SYS_DIRENT_H
#define _SYS_DIRENT_H

#include <stdint.h>

/* The kernel calls this struct dirent64 */
struct dirent {
	uint64_t	d_ino;
	int64_t		d_off;
	unsigned short	d_reclen;
	unsigned char	d_type;
	char		d_name[256];
};

/* File types to use for d_type */
#define DT_UNKNOWN	 0
#define DT_FIFO		 1
#define DT_CHR		 2
#define DT_DIR		 4
#define DT_BLK		 6
#define DT_REG		 8
#define DT_LNK		10
#define DT_SOCK		12
#define DT_WHT		14

__extern int getdents(unsigned int, struct dirent *, unsigned int);

#endif				/* _SYS_DIRENT_H */
