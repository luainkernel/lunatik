#ifndef __LINUX_LUKS_FS_H
#define __LINUX_LUKS_FS_H

/* The basic structures of the luks partition header */
#define LUKS_MAGIC_L		6
#define LUKS_CIPHERNAME_L	32
#define LUKS_CIPHERMODE_L	32
#define LUKS_HASHSPEC_L		32
#define LUKS_UUID_STRING_L	40

#define LUKS_MAGIC		"LUKS\xBA\xBE"
#define LUKS_DIGESTSIZE		20
#define LUKS_SALTSIZE		32
#define LUKS_NUMKEYS		8
#define LUKS_MKD_ITER		10
#define LUKS_KEY_DISABLED	0x0000DEAD
#define LUKS_KEY_ENABLED	0x00AC71F3
#define LUKS_STRIPES		4000

/* On-disk "super block" */
struct luks_partition_header {
	char	magic[LUKS_MAGIC_L];
	__be16	version;
	char	cipherName[LUKS_CIPHERNAME_L];
	char	cipherMode[LUKS_CIPHERMODE_L];
	char	hashSpec[LUKS_HASHSPEC_L];
	__be32	payloadOffset;
	__be32	keyBytes;
	char	mkDigest[LUKS_DIGESTSIZE];
	char	mkDigestSalt[LUKS_SALTSIZE];
	__be32	mkDigestIterations;
	char	uuid[LUKS_UUID_STRING_L];

	struct {
		__be32	active;
		/* Parameters for PBKDF2 processing */
		__be32	passwordIterations;
		char	passwordSalt[LUKS_SALTSIZE];
		__be32	keyMaterialOffset;
		__be32	stripes;
	} keyblock[LUKS_NUMKEYS];
};

#endif
