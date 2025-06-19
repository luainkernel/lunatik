/*
 * sys/splice.h
 */

#ifndef _SYS_SPLICE_H
#define _SYS_SPLICE_H

/* move pages instead of copying */
#define SPLICE_F_MOVE		1
/* don't block on the pipe splicing (but we may still block on the fd
   we splice from/to, of course */
#define SPLICE_F_NONBLOCK	2
/* expect more data */
#define SPLICE_F_MORE		4

__extern int splice(int, off_t *, int, off_t *, size_t, unsigned int);
__extern int tee(int, int, size_t, unsigned int);

#endif				/* _SYS_SPLICE_H */
