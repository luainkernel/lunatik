#ifndef __REISER4_FS_H
#define __REISER4_FS_H

#define SS_MAGIC_SIZE   16

/* reiser4 filesystem structure
 *
 * Master super block structure. It is the same for all reiser4 filesystems,
 * so, we can declare it here. It contains common for all format fields like
 * block size etc.
 */
struct reiser4_master_sb {
	/* Master super block magic. */
	char ms_magic[SS_MAGIC_SIZE];

	/* Disk format in use. */
	__u16 ms_format;

	/* Filesyetem block size in use. */
	__u16 ms_blksize;

	/* Filesyetm uuid in use. */
	char ms_uuid[SS_MAGIC_SIZE];

	/* Filesystem label in use. */
	char ms_label[SS_MAGIC_SIZE];
} __attribute__ ((packed));

#define REISER4_SUPER_MAGIC_STRING "ReIsEr4"

#endif /* __REISER4_FS_H */
