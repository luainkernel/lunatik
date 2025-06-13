#ifndef _OCFS2_FS_H
#define _OCFS2_FS_H

/* Object signatures */
#define OCFS2_SUPER_BLOCK_SIGNATURE     "OCFSV2"

#define OCFS2_VOL_UUID_LEN              16
#define OCFS2_MAX_VOL_LABEL_LEN         64

/*
 * On disk superblock for OCFS2
 * Note that it is contained inside an ocfs2_dinode, so all offsets
 * are relative to the start of ocfs2_dinode.id2.
 */
struct ocfs2_super_block {
/*00*/	uint16_t s_major_rev_level;
	uint16_t s_minor_rev_level;
	uint16_t s_mnt_count;
	int16_t s_max_mnt_count;
	uint16_t s_state;			/* File system state */
	uint16_t s_errors;			/* Behaviour when detecting errors */
	uint32_t s_checkinterval;		/* Max time between checks */
/*10*/	uint64_t s_lastcheck;		/* Time of last check */
	uint32_t s_creator_os;		/* OS */
	uint32_t s_feature_compat;		/* Compatible feature set */
/*20*/	uint32_t s_feature_incompat;	/* Incompatible feature set */
	uint32_t s_feature_ro_compat;	/* Readonly-compatible feature set */
	uint64_t s_root_blkno;		/* Offset, in blocks, of root directory
					   dinode */
/*30*/	uint64_t s_system_dir_blkno;	/* Offset, in blocks, of system
					   directory dinode */
	uint32_t s_blocksize_bits;		/* Blocksize for this fs */
	uint32_t s_clustersize_bits;	/* Clustersize for this fs */
/*40*/	uint16_t s_max_slots;		/* Max number of simultaneous mounts
					   before tunefs required */
	uint16_t s_reserved1;
	uint32_t s_reserved2;
	uint64_t s_first_cluster_group;	/* Block offset of 1st cluster
					 * group header */
/*50*/	uint8_t  s_label[OCFS2_MAX_VOL_LABEL_LEN];	/* Label for mounting, etc. */
/*90*/	uint8_t  s_uuid[OCFS2_VOL_UUID_LEN];	/* 128-bit uuid */
/*A0*/
} __attribute__ ((packed));

/*
 * On disk inode for OCFS2
 */
struct ocfs2_dinode {
/*00*/	uint8_t i_signature[8];		/* Signature for validation */
	uint32_t i_generation;		/* Generation number */
	uint16_t i_suballoc_slot;		/* Slot suballocator this inode
					   belongs to */
	int16_t i_suballoc_bit;		/* Bit offset in suballocator
					   block group */
/*10*/	uint32_t i_reserved0;
	uint32_t i_clusters;		/* Cluster count */
	uint32_t i_uid;			/* Owner UID */
	uint32_t i_gid;			/* Owning GID */
/*20*/	uint64_t i_size;			/* Size in bytes */
	uint16_t i_mode;			/* File mode */
	uint16_t i_links_count;		/* Links count */
	uint32_t i_flags;			/* File flags */
/*30*/	uint64_t i_atime;			/* Access time */
	uint64_t i_ctime;			/* Creation time */
/*40*/	uint64_t i_mtime;			/* Modification time */
	uint64_t i_dtime;			/* Deletion time */
/*50*/	uint64_t i_blkno;			/* Offset on disk, in blocks */
	uint64_t i_last_eb_blk;		/* Pointer to last extent
					   block */
/*60*/	uint32_t i_fs_generation;		/* Generation per fs-instance */
	uint32_t i_atime_nsec;
	uint32_t i_ctime_nsec;
	uint32_t i_mtime_nsec;
	uint32_t i_attr;
	uint16_t i_orphaned_slot;		/* Only valid when OCFS2_ORPHANED_FL
					   was set in i_flags */
	uint16_t i_reserved1;
/*70*/	uint64_t i_reserved2[8];
/*B8*/	uint64_t i_pad1;
	uint64_t i_rdev;	/* Device number */
	uint32_t i_used;	/* Bits (ie, clusters) used  */
	uint32_t i_total;	/* Total bits (clusters)
					   available */
	uint32_t ij_flags;	/* Mounted, version, etc. */
	uint32_t ij_pad;
/*C0*/	struct ocfs2_super_block	i_super;
/* Actual on-disk size is one block */
} __attribute__ ((packed));

#endif  /* _OCFS2_FS_H */
