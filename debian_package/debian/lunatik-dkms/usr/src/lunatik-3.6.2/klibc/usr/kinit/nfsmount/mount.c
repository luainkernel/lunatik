#include <sys/mount.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <linux/nfs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include "nfsmount.h"
#include "sunrpc.h"

static uint32_t mount_port;

struct mount_call {
	struct rpc_call rpc;
	uint32_t path_len;
	char path[0];
};

/*
 * The following structure is the NFS v3 on-the-wire file handle,
 * as defined in rfc1813.
 * This differs from the structure used by the kernel,
 * defined in <linux/nfh3.h>: rfc has a long in network order,
 * kernel has a short in native order.
 * Both kernel and rfc use the name nfs_fh; kernel name is
 * visible to user apps in some versions of libc.
 * Use different name to avoid clashes.
 */
#define NFS_MAXFHSIZE_WIRE 64
struct nfs_fh_wire {
	uint32_t size;
	char data[NFS_MAXFHSIZE_WIRE];
} __attribute__ ((packed, aligned(4)));

struct mount_reply {
	struct rpc_reply reply;
	uint32_t status;
	struct nfs_fh_wire fh;
} __attribute__ ((packed, aligned(4)));

#define MNT_REPLY_MINSIZE (sizeof(struct rpc_reply) + sizeof(uint32_t))

static int get_ports(uint32_t server, const struct nfs_mount_data *data)
{
	uint32_t nfs_ver, mount_ver;
	uint32_t proto;

	if (data->flags & NFS_MOUNT_VER3) {
		nfs_ver = NFS3_VERSION;
		mount_ver = NFS_MNT3_VERSION;
	} else {
		nfs_ver = NFS2_VERSION;
		mount_ver = NFS_MNT_VERSION;
	}

	proto = (data->flags & NFS_MOUNT_TCP) ? IPPROTO_TCP : IPPROTO_UDP;

	if (nfs_port == 0) {
		nfs_port = portmap(server, NFS_PROGRAM, nfs_ver, proto);
		if (nfs_port == 0) {
			if (proto == IPPROTO_TCP) {
				struct in_addr addr = { server };
				fprintf(stderr, "NFS over TCP not "
					"available from %s\n", inet_ntoa(addr));
				return -1;
			}
			nfs_port = NFS_PORT;
		}
	}

	if (mount_port == 0) {
		mount_port = portmap(server, NFS_MNT_PROGRAM, mount_ver, proto);
		if (mount_port == 0)
			mount_port = MOUNT_PORT;
	}
	return 0;
}

static inline int pad_len(int len)
{
	return (len + 3) & ~3;
}

static inline void dump_params(uint32_t server,
			       const char *path,
			       const struct nfs_mount_data *data)
{
	(void)server;
	(void)path;
	(void)data;

#ifdef DEBUG
	struct in_addr addr = { server };

	printf("NFS params:\n");
	printf("  server = %s, path = \"%s\", ", inet_ntoa(addr), path);
	printf("version = %d, proto = %s\n",
	       data->flags & NFS_MOUNT_VER3 ? 3 : 2,
	       (data->flags & NFS_MOUNT_TCP) ? "tcp" : "udp");
	printf("  mount_port = %d, nfs_port = %d, flags = %08x\n",
	       mount_port, nfs_port, data->flags);
	printf("  rsize = %d, wsize = %d, timeo = %d, retrans = %d\n",
	       data->rsize, data->wsize, data->timeo, data->retrans);
	printf("  acreg (min, max) = (%d, %d), acdir (min, max) = (%d, %d)\n",
	       data->acregmin, data->acregmax, data->acdirmin, data->acdirmax);
	printf("  soft = %d, intr = %d, posix = %d, nocto = %d, noac = %d\n",
	       (data->flags & NFS_MOUNT_SOFT) != 0,
	       (data->flags & NFS_MOUNT_INTR) != 0,
	       (data->flags & NFS_MOUNT_POSIX) != 0,
	       (data->flags & NFS_MOUNT_NOCTO) != 0,
	       (data->flags & NFS_MOUNT_NOAC) != 0);
#endif
}

static inline void dump_fh(const char *data, int len)
{
	(void)data;
	(void)len;

#ifdef DEBUG
	int i = 0;
	int max = len - (len % 8);

	printf("Root file handle: %d bytes\n", NFS2_FHSIZE);

	while (i < max) {
		int j;

		printf("  %4d:  ", i);
		for (j = 0; j < 4; j++) {
			printf("%02x %02x %02x %02x  ",
			       data[i] & 0xff, data[i + 1] & 0xff,
			       data[i + 2] & 0xff, data[i + 3] & 0xff);
		}
		i += j;
		printf("\n");
	}
#endif
}

static struct mount_reply mnt_reply;

static int mount_call(uint32_t proc, uint32_t version,
		      const char *path, struct client *clnt)
{
	struct mount_call *mnt_call = NULL;
	size_t path_len, call_len;
	struct rpc rpc;
	int ret = 0;

	path_len = strlen(path);
	call_len = sizeof(*mnt_call) + pad_len(path_len);

	mnt_call = malloc(call_len);
	if (mnt_call == NULL) {
		perror("malloc");
		goto bail;
	}

	memset(mnt_call, 0, sizeof(*mnt_call));

	mnt_call->rpc.program = htonl(NFS_MNT_PROGRAM);
	mnt_call->rpc.prog_vers = htonl(version);
	mnt_call->rpc.proc = htonl(proc);
	mnt_call->path_len = htonl(path_len);
	memcpy(mnt_call->path, path, path_len);

	rpc.call = (struct rpc_call *)mnt_call;
	rpc.call_len = call_len;
	rpc.reply = (struct rpc_reply *)&mnt_reply;
	rpc.reply_len = sizeof(mnt_reply);

	if (rpc_call(clnt, &rpc) < 0)
		goto bail;

	if (proc != MNTPROC_MNT)
		goto done;

	if (rpc.reply_len < MNT_REPLY_MINSIZE) {
		fprintf(stderr, "incomplete reply: %zu < %zu\n",
			rpc.reply_len, MNT_REPLY_MINSIZE);
		goto bail;
	}

	if (mnt_reply.status != 0) {
		fprintf(stderr, "mount call failed - server replied: %s.\n",
			strerror(ntohl(mnt_reply.status)));
		goto bail;
	}

	goto done;

bail:
	ret = -1;

done:
	if (mnt_call)
		free(mnt_call);

	return ret;
}

static int mount_v2(const char *path,
		    struct nfs_mount_data *data, struct client *clnt)
{
	int ret = mount_call(MNTPROC_MNT, NFS_MNT_VERSION, path, clnt);

	if (ret == 0) {
		dump_fh((const char *)&mnt_reply.fh, NFS2_FHSIZE);

		data->root.size = NFS_FHSIZE;
		memcpy(data->root.data, &mnt_reply.fh, NFS_FHSIZE);
		memcpy(data->old_root.data, &mnt_reply.fh, NFS_FHSIZE);
	}

	return ret;
}

static inline int umount_v2(const char *path, struct client *clnt)
{
	return mount_call(MNTPROC_UMNT, NFS_MNT_VERSION, path, clnt);
}

static int mount_v3(const char *path,
		    struct nfs_mount_data *data, struct client *clnt)
{
	int ret = mount_call(MNTPROC_MNT, NFS_MNT3_VERSION, path, clnt);

	if (ret == 0) {
		size_t fhsize = ntohl(mnt_reply.fh.size);

		dump_fh((const char *)&mnt_reply.fh.data, fhsize);

		memset(data->old_root.data, 0, NFS_FHSIZE);
		memset(&data->root, 0, sizeof(data->root));
		data->root.size = fhsize;
		memcpy(&data->root.data, mnt_reply.fh.data, fhsize);
		data->flags |= NFS_MOUNT_VER3;
	}

	return ret;
}

static inline int umount_v3(const char *path, struct client *clnt)
{
	return mount_call(MNTPROC_UMNT, NFS_MNT3_VERSION, path, clnt);
}

int nfs_mount(const char *pathname, const char *hostname,
	      uint32_t server, const char *rem_path, const char *path,
	      struct nfs_mount_data *data)
{
	struct client *clnt = NULL;
	struct sockaddr_in addr;
	char mounted = 0;
	int sock = -1;
	int ret = 0;
	int mountflags;

	if (get_ports(server, data) != 0)
		goto bail;

	dump_params(server, rem_path, data);

	if (data->flags & NFS_MOUNT_TCP)
		clnt = tcp_client(server, mount_port, CLI_RESVPORT);
	else
		clnt = udp_client(server, mount_port, CLI_RESVPORT);

	if (clnt == NULL)
		goto bail;

	if (data->flags & NFS_MOUNT_VER3)
		ret = mount_v3(rem_path, data, clnt);
	else
		ret = mount_v2(rem_path, data, clnt);

	if (ret == -1)
		goto bail;
	mounted = 1;

	if (data->flags & NFS_MOUNT_TCP)
		sock = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
	else
		sock = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);

	if (sock == -1) {
		perror("socket");
		goto bail;
	}

	if (bindresvport(sock, 0) == -1) {
		perror("bindresvport");
		goto bail;
	}

	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = server;
	addr.sin_port = htons(nfs_port);
	memcpy(&data->addr, &addr, sizeof(data->addr));

	strncpy(data->hostname, hostname, sizeof(data->hostname));

	data->fd = sock;

	mountflags = (data->flags & NFS_MOUNT_KLIBC_RONLY) ? MS_RDONLY : 0;
	data->flags = data->flags & NFS_MOUNT_FLAGMASK;
	ret = mount(pathname, path, "nfs", mountflags, data);

	if (ret == -1) {
		if (errno == ENODEV) {
			fprintf(stderr, "mount: the kernel lacks NFS v%d "
				"support\n",
				(data->flags & NFS_MOUNT_VER3) ? 3 : 2);
		} else {
			perror("mount");
		}
		goto bail;
	}

	dprintf("Mounted %s on %s\n", pathname, path);

	goto done;

bail:
	if (mounted) {
		if (data->flags & NFS_MOUNT_VER3)
			umount_v3(rem_path, clnt);
		else
			umount_v2(rem_path, clnt);
	}

	ret = -1;

done:
	if (clnt)
		client_free(clnt);

	if (sock != -1)
		close(sock);

	return ret;
}
