/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2006 H. Peter Anvin - All Rights Reserved
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 53 Temple Place Ste 330,
 *   Boston MA 02111-1307, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * sys/md.h
 *
 * Defines for the Linux md functionality.  Some of this stuff is
 * userspace-visible but lives in md_k.h, which is user-space unsafe.
 * Sigh.
 */

#ifndef _SYS_MD_H
#define _SYS_MD_H

#include <sys/types.h>

#define LEVEL_MULTIPATH         (-4)
#define LEVEL_LINEAR            (-1)
#define LEVEL_FAULTY            (-5)
#define MAX_MD_DEVS  256	/* Max number of md dev */

#include <linux/raid/md_u.h>
#include <linux/raid/md_p.h>

#endif				/* _SYS_MD_H */
