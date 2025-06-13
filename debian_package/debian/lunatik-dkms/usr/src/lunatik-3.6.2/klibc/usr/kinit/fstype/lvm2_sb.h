#ifndef __LVM2_SB_H
#define __LVM2_SB_H

/* LVM2 super block definitions */
#define LVM2_MAGIC_L		8
#define LVM2_MAGIC		"LABELONE"
#define LVM2_TYPE_L		8
#define LVM2_TYPE		"LVM2 001"

struct lvm2_super_block {
	char magic[LVM2_MAGIC_L];
	__be64 sector;
	__be32 crc;
	__be32 offset;
	char type[LVM2_TYPE_L];
};

#endif
