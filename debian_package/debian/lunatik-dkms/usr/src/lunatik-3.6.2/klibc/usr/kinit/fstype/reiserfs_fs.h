#ifndef __REISERFS_FS_H
#define __REISERFS_FS_H

struct journal_params {
	__u32 jp_journal_1st_block;	/* where does journal start from on its
					 * device */
	__u32 jp_journal_dev;	/* journal device st_rdev */
	__u32 jp_journal_size;	/* size of the journal */
	__u32 jp_journal_trans_max;	/* max number of blocks in a transaction. */
	__u32 jp_journal_magic;	/* random value made on fs creation (this
				 * was sb_journal_block_count) */
	__u32 jp_journal_max_batch;	/* max number of blocks to batch into a
					 * trans */
	__u32 jp_journal_max_commit_age;	/* in seconds, how old can an async
						 * commit be */
	__u32 jp_journal_max_trans_age;	/* in seconds, how old can a transaction
					 * be */
};

/* this is the super from 3.5.X, where X >= 10 */
struct reiserfs_super_block_v1 {
	__u32 s_block_count;	/* blocks count         */
	__u32 s_free_blocks;	/* free blocks count    */
	__u32 s_root_block;	/* root block number    */
	struct journal_params s_journal;
	__u16 s_blocksize;	/* block size */
	__u16 s_oid_maxsize;	/* max size of object id array, see
				 * get_objectid() commentary  */
	__u16 s_oid_cursize;	/* current size of object id array */
	__u16 s_umount_state;	/* this is set to 1 when filesystem was
				 * umounted, to 2 - when not */
	char s_magic[10];	/* reiserfs magic string indicates that
				 * file system is reiserfs:
				 * "ReIsErFs" or "ReIsEr2Fs" or "ReIsEr3Fs" */
	__u16 s_fs_state;	/* it is set to used by fsck to mark which
				 * phase of rebuilding is done */
	__u32 s_hash_function_code;	/* indicate, what hash function is being use
					 * to sort names in a directory*/
	__u16 s_tree_height;	/* height of disk tree */
	__u16 s_bmap_nr;	/* amount of bitmap blocks needed to address
				 * each block of file system */
	__u16 s_version;	/* this field is only reliable on filesystem
				 * with non-standard journal */
	__u16 s_reserved_for_journal;	/* size in blocks of journal area on main
					 * device, we need to keep after
					 * making fs with non-standard journal */
} __attribute__ ((__packed__));

/* this is the on disk super block */
struct reiserfs_super_block {
	struct reiserfs_super_block_v1 s_v1;
	__u32 s_inode_generation;
	__u32 s_flags;		/* Right now used only by inode-attributes, if enabled */
	unsigned char s_uuid[16];	/* filesystem unique identifier */
	unsigned char s_label[16];	/* filesystem volume label */
	char s_unused[88];	/* zero filled by mkreiserfs and
				 * reiserfs_convert_objectid_map_v1()
				 * so any additions must be updated
				 * there as well. */
} __attribute__ ((__packed__));

#define REISERFS_SUPER_MAGIC_STRING "ReIsErFs"
#define REISER2FS_SUPER_MAGIC_STRING "ReIsEr2Fs"
#define REISER2FS_JR_SUPER_MAGIC_STRING "ReIsEr3Fs"

#define SB_V1_DISK_SUPER_BLOCK(s) (&((s)->s_v1))
#define REISERFS_BLOCKSIZE(s) \
        __le32_to_cpu((SB_V1_DISK_SUPER_BLOCK(s)->s_blocksize))
#define REISERFS_BLOCK_COUNT(s) \
        __le32_to_cpu((SB_V1_DISK_SUPER_BLOCK(s)->s_block_count))
#define REISERFS_MAGIC(s) \
        (SB_V1_DISK_SUPER_BLOCK(s)->s_magic)

#endif /* __REISERFS_FS_H */
