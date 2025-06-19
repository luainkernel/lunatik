#ifndef __XFS_SB_H
#define __XFS_SB_H

/*
 * Super block
 * Fits into a sector-sized buffer at address 0 of each allocation group.
 * Only the first of these is ever updated except during growfs.
 */

struct xfs_buf;
struct xfs_mount;

#define	XFS_SB_MAGIC		0x58465342	/* 'XFSB' */

typedef struct xfs_sb {
	__u32 sb_magicnum;	/* magic number == XFS_SB_MAGIC */
	__u32 sb_blocksize;	/* logical block size, bytes */
	__u64 sb_dblocks;	/* number of data blocks */
} xfs_sb_t;

#endif /* __XFS_SB_H */
