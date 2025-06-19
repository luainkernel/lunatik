/*
 * sys/sendfile.h
 */

#ifndef _SYS_SENDFILE_H
#define _SYS_SENDFILE_H

#include <klibc/extern.h>
#include <stddef.h>
#include <sys/types.h>

__extern ssize_t sendfile(int, int, off_t *, size_t, off_t);

#endif /* _SYS_SENDFILE_H */
