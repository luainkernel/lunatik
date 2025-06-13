/*
 * Enough portmapper functionality that mount doesn't hang trying
 * to start lockd.  Enables nfsroot with locking functionality.
 *
 * Note: the kernel will only speak to the local portmapper
 * using RPC over UDP.
 */

#include <sys/types.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <string.h>
#include <sys/socket.h>

#include "dummypmap.h"
#include "sunrpc.h"

extern const char *progname;

struct portmap_args {
	uint32_t program;
	uint32_t version;
	uint32_t proto;
	uint32_t port;
};

struct portmap_call {
	struct rpc_call rpc;
	struct portmap_args args;
};

struct portmap_reply {
	struct rpc_reply rpc;
	uint32_t port;
};

static int bind_portmap(void)
{
	int sock = socket(PF_INET, SOCK_DGRAM, 0);
	struct sockaddr_in sin;

	if (sock < 0)
		return -1;

	memset(&sin, 0, sizeof sin);
	sin.sin_family = AF_INET;
	sin.sin_addr.s_addr = htonl(0x7f000001);	/* 127.0.0.1 */
	sin.sin_port = htons(RPC_PMAP_PORT);
	if (bind(sock, (struct sockaddr *)&sin, sizeof sin) < 0) {
		int err = errno;
		close(sock);
		errno = err;
		return -1;
	}

	return sock;
}

static const char *protoname(uint32_t proto)
{
	switch (ntohl(proto)) {
	case IPPROTO_TCP:
		return "tcp";
	case IPPROTO_UDP:
		return "udp";
	default:
		return NULL;
	}
}

static void *get_auth(struct rpc_auth *auth)
{
	switch (ntohl(auth->flavor)) {
	case AUTH_NULL:
	/* Fallthrough */
	case AUTH_UNIX:
		return (char *)&auth->body + ntohl(auth->len);
	default:
		return NULL;
	}
}

static int check_unix_cred(struct rpc_auth *cred)
{
	uint32_t len;
	int quad_len;
	uint32_t node_name_len;
	int quad_name_len;
	uint32_t *base;
	uint32_t *pos;
	int ret = -1;

	len = ntohl(cred->len);
	quad_len = (len + 3) >> 2;
	if (quad_len < 6)
		/* Malformed creds */
		goto out;

	base = pos = cred->body;

	/* Skip timestamp */
	pos++;

	/* Skip node name: only localhost can succeed. */
	node_name_len = ntohl(*pos++);
	quad_name_len = (node_name_len + 3) >> 2;
	if (pos + quad_name_len + 3 > base + quad_len)
		/* Malformed creds */
		goto out;
	pos += quad_name_len;

	/* uid must be 0 */
	if (*pos++ != 0)
		goto out;

	/* gid must be 0 */
	if (*pos++ != 0)
		goto out;

	/* Skip remaining gids */
	ret = 0;

out:
	return ret;
}

static int check_cred(struct rpc_auth *cred)
{
	switch (ntohl(cred->flavor)) {
	case AUTH_NULL:
		return 0;
	case AUTH_UNIX:
		return check_unix_cred(cred);
	default:
		return -1;
	}
}

static int check_vrf(struct rpc_auth *vrf)
{
	return (vrf->flavor == htonl(AUTH_NULL)) ? 0 : -1;
}

#define MAX_UDP_PACKET	65536

static int dummy_portmap(int sock, FILE *portmap_file)
{
	enum { PAYLOAD_SIZE = MAX_UDP_PACKET + offsetof(struct rpc_header, udp) };
	struct sockaddr_in sin;
	int pktlen, addrlen;
	union {
		struct rpc_call rpc;
		/* Max UDP packet size + unused TCP fragment size */
		char payload[PAYLOAD_SIZE];
	} pkt;
	struct rpc_call *rpc = &pkt.rpc;
	struct rpc_auth *cred;
	struct rpc_auth *vrf;
	struct portmap_args *args;
	struct portmap_reply rply;

	for (;;) {
		addrlen = sizeof sin;
		pktlen = recvfrom(sock, &rpc->hdr.udp, MAX_UDP_PACKET,
				  0, (struct sockaddr *)&sin, &addrlen);

		if (pktlen < 0) {
			if (errno == EINTR)
				continue;

			return -1;
		}

		/* +4 to skip the TCP fragment header */
		if (pktlen + 4 < sizeof(struct portmap_call))
			continue;	/* Bad packet */

		if (rpc->hdr.udp.msg_type != htonl(RPC_CALL))
			continue;	/* Bad packet */

		memset(&rply, 0, sizeof rply);

		rply.rpc.hdr.udp.xid = rpc->hdr.udp.xid;
		rply.rpc.hdr.udp.msg_type = htonl(RPC_REPLY);

		cred = (struct rpc_auth *) &rpc->cred_flavor;
		if (rpc->rpc_vers != htonl(2)) {
			rply.rpc.reply_state = htonl(REPLY_DENIED);
			/* state <- RPC_MISMATCH == 0 */
		} else if (rpc->program != htonl(PORTMAP_PROGRAM)) {
			rply.rpc.reply_state = htonl(PROG_UNAVAIL);
		} else if (rpc->prog_vers != htonl(2)) {
			rply.rpc.reply_state = htonl(PROG_MISMATCH);
		} else if (!(vrf = get_auth(cred)) ||
			   (char *)vrf > ((char *)&rpc->hdr.udp + pktlen - 8 -
					  sizeof(*args)) ||
			   !(args = get_auth(vrf)) ||
			   (char *)args > ((char *)&rpc->hdr.udp + pktlen -
					   sizeof(*args)) ||
			   check_cred(cred) || check_vrf(vrf)) {
			/* Can't deal with credentials data; the kernel
			   won't send them */
			rply.rpc.reply_state = htonl(SYSTEM_ERR);
		} else {
			switch (ntohl(rpc->proc)) {
			case PMAP_PROC_NULL:
				break;
			case PMAP_PROC_SET:
				if (args->proto == htonl(IPPROTO_TCP) ||
				    args->proto == htonl(IPPROTO_UDP)) {
					if (portmap_file)
						fprintf(portmap_file,
							"%u %u %s %u\n",
							ntohl(args->program),
							ntohl(args->version),
							protoname(args->proto),
							ntohl(args->port));
					rply.port = htonl(1);	/* TRUE = success */
				}
				break;
			case PMAP_PROC_UNSET:
				rply.port = htonl(1);	/* TRUE = success */
				break;
			case PMAP_PROC_GETPORT:
				break;
			case PMAP_PROC_DUMP:
				break;
			default:
				rply.rpc.reply_state = htonl(PROC_UNAVAIL);
				break;
			}
		}

		sendto(sock, &rply.rpc.hdr.udp, sizeof rply - 4, 0,
		       (struct sockaddr *)&sin, addrlen);
	}
}

pid_t start_dummy_portmap(const char *file)
{
	FILE *portmap_filep;
	int sock;
	pid_t spoof_portmap;

	portmap_filep = fopen(file, "w");
	if (!portmap_filep) {
		fprintf(stderr, "%s: cannot write portmap file: %s\n",
			progname, file);
		return -1;
	}

	sock = bind_portmap();
	if (sock == -1) {
		if (errno == EINVAL || errno == EADDRINUSE)
			return 0;	/* Assume not needed */
		else {
			fclose(portmap_filep);
			fprintf(stderr, "%s: portmap spoofing failed\n",
				progname);
			return -1;
		}
	}

	spoof_portmap = fork();
	if (spoof_portmap == -1) {
		fclose(portmap_filep);
		fprintf(stderr, "%s: cannot fork\n", progname);
		return -1;
	} else if (spoof_portmap == 0) {
		/* Child process */
		dummy_portmap(sock, portmap_filep);
		_exit(255);	/* Error */
	} else {
		/* Parent process */
		close(sock);
		return spoof_portmap;
	}
}
