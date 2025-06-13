#ifndef __GFS2_FS_H
#define __GFS2_FS_H

#define GFS2_MAGIC              0x01161970
#define GFS2_FORMAT_FS		1801
#define GFS2_FORMAT_MULTI	1900


/*
 * An on-disk inode number
 */
struct gfs2_inum {
	__be64 no_formal_ino;
	__be64 no_addr;
};

/*
 * Generic metadata head structure
 * Every inplace buffer logged in the journal must start with this.
 */
struct gfs2_meta_header {
	uint32_t mh_magic;
	uint32_t mh_type;
	uint64_t __pad0;          /* Was generation number in gfs1 */
	uint32_t mh_format;
	uint32_t __pad1;          /* Was incarnation number in gfs1 */
};

/* Requirement:  GFS2_LOCKNAME_LEN % 8 == 0
 *    Includes: the fencing zero at the end */
#define GFS2_LOCKNAME_LEN       64

/*
 * super-block structure
 */
struct gfs2_sb {
	struct gfs2_meta_header sb_header;

	uint32_t sb_fs_format;
	uint32_t sb_multihost_format;
	uint32_t  __pad0;  /* Was superblock flags in gfs1 */

	uint32_t sb_bsize;
	uint32_t sb_bsize_shift;
	uint32_t __pad1;   /* Was journal segment size in gfs1 */

	struct gfs2_inum sb_master_dir; /* Was jindex dinode in gfs1 */
	struct gfs2_inum __pad2; /* Was rindex dinode in gfs1 */
	struct gfs2_inum sb_root_dir;

	char sb_lockproto[GFS2_LOCKNAME_LEN];
	char sb_locktable[GFS2_LOCKNAME_LEN];
	/* In gfs1, quota and license dinodes followed */
} __attribute__ ((__packed__));

#endif /* __GFS2_FS_H */
