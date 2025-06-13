#include <arpa/inet.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "kinit.h"
#include "netdev.h"
#include "nfsmount.h"

static char *sub_client(__u32 client, char *path, size_t len)
{
	struct in_addr addr = { client };
	char buf[len];

	if (strstr(path, "%s") != NULL) {
		if (client == INADDR_NONE) {
			fprintf(stderr, "Root-NFS: no client address\n");
			exit(1);
		}

		snprintf(buf, len, path, inet_ntoa(addr));
		strcpy(path, buf);
	}

	return path;
}

#define NFS_ARGC 6
#define MOUNT_POINT "/root"

int mount_nfs_root(int argc, char *argv[], int flags)
{
	(void)flags;		/* FIXME - don't ignore this */

	struct in_addr addr = { INADDR_NONE };
	__u32 client = INADDR_NONE;
	const int len = 1024;
	struct netdev *dev;
	char *mtpt = MOUNT_POINT;
	char *path = NULL;
	char *dev_bootpath = NULL;
	char root[len];
	char *x, *opts;
	int ret = 0;
	int a = 1;
	char *nfs_argv[NFS_ARGC + 1] = { "NFS-Mount" };

	for (dev = ifaces; dev; dev = dev->next) {
		if (dev->ip_server != INADDR_NONE &&
		    dev->ip_server != INADDR_ANY) {
			addr.s_addr = dev->ip_server;
			client = dev->ip_addr;
			dev_bootpath = dev->bootpath;
			break;
		}
		if (dev->ip_addr != INADDR_NONE && dev->ip_addr != INADDR_ANY)
			client = dev->ip_addr;
	}

	/*
	 * if the "nfsroot" option is set then it overrides
	 * bootpath supplied by the boot server.
	 */
	if ((path = get_arg(argc, argv, "nfsroot=")) == NULL) {
		if ((path = dev_bootpath) == NULL || path[0] == '\0')
			/* no path - set a default */
			path = (char *)"/tftpboot/%s";
	} else if (dev_bootpath && dev_bootpath[0] != '\0')
		fprintf(stderr,
			"nfsroot=%s overrides boot server bootpath %s\n",
			path, dev_bootpath);

	if ((opts = strchr(path, ',')) != NULL) {
		*opts++ = '\0';
		nfs_argv[a++] = (char *)"-o";
		nfs_argv[a++] = opts;
	}

	if ((x = strchr(path, ':')) == NULL) {
		if (addr.s_addr == INADDR_NONE) {
			fprintf(stderr, "Root-NFS: no server defined\n");
			exit(1);
		}

		snprintf(root, len, "%s:%s", inet_ntoa(addr), path);
	} else {
		strcpy(root, path);
	}

	nfs_argv[a++] = sub_client(client, root, len);

	dprintf("NFS-Root: mounting %s on %s with options \"%s\"\n",
		nfs_argv[a-1], mtpt, opts ? opts : "");

	nfs_argv[a++] = mtpt;
	nfs_argv[a] = NULL;
	assert(a <= NFS_ARGC);

	dump_args(a, nfs_argv);

	if ((ret = nfsmount_main(a, nfs_argv)) != 0) {
		ret = -1;
		goto done;
	}

done:
	return ret;
}
