#include <sys/types.h>
#include <netinet/in.h>
#include <asm/byteorder.h>	/* __constant_hton* */
#include <stdio.h>
#include <stdlib.h>

#include "nfsmount.h"
#include "sunrpc.h"

struct portmap_call {
	struct rpc_call rpc;
	uint32_t program;
	uint32_t version;
	uint32_t proto;
	uint32_t port;
};

struct portmap_reply {
	struct rpc_reply rpc;
	uint32_t port;
};

static struct portmap_call call = {
	.rpc = {
		.program	= __constant_htonl(RPC_PMAP_PROGRAM),
		.prog_vers	= __constant_htonl(RPC_PMAP_VERSION),
		.proc		= __constant_htonl(PMAP_PROC_GETPORT),
	}
};

uint32_t portmap(uint32_t server, uint32_t program, uint32_t version, uint32_t proto)
{
	struct portmap_reply reply;
	struct client *clnt;
	struct rpc rpc;
	uint32_t port = 0;

	clnt = tcp_client(server, RPC_PMAP_PORT, 0);
	if (clnt == NULL) {
		clnt = udp_client(server, RPC_PMAP_PORT, 0);
		if (clnt == NULL)
			goto bail;
	}

	call.program = htonl(program);
	call.version = htonl(version);
	call.proto = htonl(proto);

	rpc.call = (struct rpc_call *)&call;
	rpc.call_len = sizeof(call);
	rpc.reply = (struct rpc_reply *)&reply;
	rpc.reply_len = sizeof(reply);

	if (rpc_call(clnt, &rpc) < 0)
		goto bail;

	if (rpc.reply_len < sizeof(reply)) {
		fprintf(stderr, "incomplete reply: %zu < %zu\n",
			rpc.reply_len, sizeof(reply));
		goto bail;
	}

	port = ntohl(reply.port);

bail:
	dprintf("Port for %d/%d[%s]: %d\n", program, version,
		proto == IPPROTO_TCP ? "tcp" : "udp", port);

	if (clnt)
		client_free(clnt);

	return port;
}
