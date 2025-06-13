#ifndef NFSMOUNT_NFSMOUNT_H
#define NFSMOUNT_NFSMOUNT_H

#include <linux/nfs_mount.h>

extern int nfs_port;

extern int nfsmount_main(int argc, char *argv[]);
int nfs_mount(const char *rem_name, const char *hostname,
	      uint32_t server, const char *rem_path,
	      const char *path, struct nfs_mount_data *data);

enum nfs_proto {
	v2 = 2,
	v3,
};

/* masked with NFS_MOUNT_FLAGMASK before mount() call */
#define NFS_MOUNT_KLIBC_RONLY	0x00010000U

#ifdef DEBUG
# define dprintf printf
#else
# define dprintf(...) ((void)0)
#endif

#ifndef MNTPROC_MNT
#define MNTPROC_MNT 1
#endif
#ifndef MNTPROC_UMNT
#define MNTPROC_UMNT 3
#endif

#endif /* NFSMOUNT_NFSMOUNT_H */
