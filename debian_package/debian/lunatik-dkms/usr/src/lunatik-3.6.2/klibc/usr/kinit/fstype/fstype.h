/*
 * by rmk
 *
 * Detect filesystem type (on stdin) and output strings for two
 * environment variables:
 *  FSTYPE - filesystem type
 *  FSSIZE - filesystem size (if known)
 *
 * We currently detect the fs listed in struct imagetype.
 */

#ifndef FSTYPE_H
#define FSTYPE_H

#include <unistd.h>

int identify_fs(int fd, const char **fstype,
		unsigned long long *bytes, off_t offset);

#endif
