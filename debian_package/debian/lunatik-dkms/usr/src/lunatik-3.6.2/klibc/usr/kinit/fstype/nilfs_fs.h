#ifndef __NILFS_FS_H
#define __NILFS_FS_H

#define NILFS_SUPER_MAGIC       0x3434  /* NILFS filesystem  magic number */

/*
 * struct nilfs_super_block - structure of super block on disk
 */
struct nilfs_super_block {
	__le32	s_rev_level;		/* Revision level */
	__le16	s_minor_rev_level;	/* minor revision level */
	__le16	s_magic;		/* Magic signature */

	__le16  s_bytes;		/* Bytes count of CRC calculation
					   for this structure. s_reserved
					   is excluded. */
	__le16  s_flags;		/* flags */
	__le32  s_crc_seed;		/* Seed value of CRC calculation */
	__le32	s_sum;			/* Check sum of super block */

	__le32	s_log_block_size;	/* Block size represented as follows
					   blocksize = 1 << (s_log_block_size + 10) */
	__le64  s_nsegments;		/* Number of segments in filesystem */
	__le64  s_dev_size;		/* block device size in bytes */
	__le64	s_first_data_block;	/* 1st seg disk block number */
	__le32  s_blocks_per_segment;   /* number of blocks per full segment */
	__le32	s_r_segments_percentage;/* Reserved segments percentage */ /* or __le16 */

	__le64  s_last_cno;		/* Last checkpoint number */
	__le64  s_last_pseg;		/* disk block addr pseg written last */
	__le64  s_last_seq;             /* seq. number of seg written last */
	__le64	s_free_blocks_count;	/* Free blocks count */

	__le64	s_ctime;		/* Creation time (execution time of newfs) */
	__le64	s_mtime;		/* Mount time */
	__le64	s_wtime;		/* Write time */
	__le16	s_mnt_count;		/* Mount count */
	__le16	s_max_mnt_count;	/* Maximal mount count */
	__le16	s_state;		/* File system state */
	__le16	s_errors;		/* Behaviour when detecting errors */
	__le64	s_lastcheck;		/* time of last check */

	__le32	s_checkinterval;	/* max. time between checks */
	__le32	s_creator_os;		/* OS */
	__le16	s_def_resuid;		/* Default uid for reserved blocks */
	__le16	s_def_resgid;		/* Default gid for reserved blocks */
	__le32	s_first_ino; 		/* First non-reserved inode */ /* or __le16 */

	__le16  s_inode_size; 		/* Size of an inode */
	__le16  s_dat_entry_size;       /* Size of a dat entry */
	__le16  s_checkpoint_size;      /* Size of a checkpoint */
	__le16	s_segment_usage_size;	/* Size of a segment usage */

	__u8	s_uuid[16];		/* 128-bit uuid for volume */
	char	s_volume_name[16]; 	/* volume name */
	char	s_last_mounted[64]; 	/* directory where last mounted */

	__le32  s_c_interval;           /* Commit interval of segment */
	__le32  s_c_block_max;          /* Threshold of data amount for
					   the segment construction */
	__u32	s_reserved[192];	/* padding to the end of the block */
};

#endif /* __NILFS_FS_H */
