#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "nfsmount.h"
#include "sunrpc.h"

/*
 * The magic offset is needed here because RPC over TCP includes a
 * field that RPC over UDP doesn't.  Luvverly.
 */
static int rpc_do_reply(struct client *clnt, struct rpc *rpc, size_t off)
{
	int ret;

	if ((ret = read(clnt->sock,
			((char *)rpc->reply) + off,
			rpc->reply_len - off)) == -1) {
		perror("read");
		goto bail;
	} else if (ret < sizeof(struct rpc_reply) - off) {
		fprintf(stderr, "short read: %d < %zu\n", ret,
			sizeof(struct rpc_reply) - off);
		goto bail;
	}
	rpc->reply_len = ret + off;

	if ((!off && !(ntohl(rpc->reply->hdr.frag_hdr) & LAST_FRAG)) ||
	    rpc->reply->hdr.udp.xid != rpc->call->hdr.udp.xid ||
	    rpc->reply->hdr.udp.msg_type != htonl(RPC_REPLY)) {
		fprintf(stderr, "bad reply\n");
		goto bail;
	}

	if (ntohl(rpc->reply->state) != REPLY_OK) {
		fprintf(stderr, "rpc failed: %d\n", ntohl(rpc->reply->state));
		goto bail;
	}

	ret = 0;
	goto done;

bail:
	ret = -1;
done:
	return ret;
}

static void rpc_header(struct client *clnt, struct rpc *rpc)
{
	(void)clnt;

	rpc->call->hdr.frag_hdr = htonl(LAST_FRAG | (rpc->call_len - 4));
	rpc->call->hdr.udp.xid = lrand48();
	rpc->call->hdr.udp.msg_type = htonl(RPC_CALL);
	rpc->call->rpc_vers = htonl(2);
}

static int rpc_call_tcp(struct client *clnt, struct rpc *rpc)
{
	int ret;

	rpc_header(clnt, rpc);

	if ((ret = write(clnt->sock, rpc->call, rpc->call_len)) == -1) {
		perror("write");
		goto bail;
	} else if (ret < rpc->call_len) {
		fprintf(stderr, "short write: %d < %zu\n", ret, rpc->call_len);
		goto bail;
	}

	ret = rpc_do_reply(clnt, rpc, 0);
	goto done;

      bail:
	ret = -1;

      done:
	return ret;
}

static int rpc_call_udp(struct client *clnt, struct rpc *rpc)
{
#define NR_FDS 1
#define TIMEOUT_MS 3000
#define MAX_TRIES 100
#define UDP_HDR_OFF (sizeof(struct rpc_header) - sizeof(struct rpc_udp_header))
	struct pollfd fds[NR_FDS];
	int ret = -1;
	int i;

	rpc_header(clnt, rpc);

	fds[0].fd = clnt->sock;
	fds[0].events = POLLRDNORM;

	rpc->call_len -= UDP_HDR_OFF;

	for (i = 0; i < MAX_TRIES; i++) {
		int timeout_ms = TIMEOUT_MS + (lrand48() % (TIMEOUT_MS / 2));
		if ((ret = write(clnt->sock,
				 ((char *)rpc->call) + UDP_HDR_OFF,
				 rpc->call_len)) == -1) {
			perror("write");
			goto bail;
		} else if (ret < rpc->call_len) {
			fprintf(stderr, "short write: %d < %zu\n", ret,
				rpc->call_len);
			goto bail;
		}
		for (; i < MAX_TRIES; i++) {
			if ((ret = poll(fds, NR_FDS, timeout_ms)) == -1) {
				perror("poll");
				goto bail;
			}
			if (ret == 0) {
				dprintf("Timeout #%d\n", i + 1);
				break;
			}
			if ((ret = rpc_do_reply(clnt, rpc, UDP_HDR_OFF)) == 0) {
				goto done;
			} else {
				dprintf("Failed on try #%d - retrying\n",
					i + 1);
			}
		}
	}

      bail:
	ret = -1;

      done:
	return ret;
}

struct client *tcp_client(uint32_t server, uint16_t port, uint32_t flags)
{
	struct client *clnt = malloc(sizeof(*clnt));
	struct sockaddr_in addr;
	int sock;

	if (clnt == NULL) {
		perror("malloc");
		goto bail;
	}

	memset(clnt, 0, sizeof(*clnt));

	if ((sock = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP)) == -1) {
		perror("socket");
		goto bail;
	}

	if ((flags & CLI_RESVPORT) && bindresvport(sock, 0) == -1) {
		perror("bindresvport");
		goto bail;
	}

	clnt->sock = sock;
	clnt->call_stub = rpc_call_tcp;

	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = server;

	if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
		perror("connect");
		goto bail;
	}

	goto done;
      bail:
	if (clnt) {
		free(clnt);
		clnt = NULL;
	}
      done:
	return clnt;
}

struct client *udp_client(uint32_t server, uint16_t port, uint32_t flags)
{
	struct client *clnt = malloc(sizeof(*clnt));
	struct sockaddr_in addr;
	int sock;

	if (clnt == NULL) {
		perror("malloc");
		goto bail;
	}

	memset(clnt, 0, sizeof(*clnt));

	if ((sock = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP)) == -1) {
		perror("socket");
		goto bail;
	}

	if ((flags & CLI_RESVPORT) && bindresvport(sock, 0) == -1) {
		perror("bindresvport");
		goto bail;
	} else {
		struct sockaddr_in me;

		me.sin_family = AF_INET;
		me.sin_port = 0;
		me.sin_addr.s_addr = INADDR_ANY;

		if (0 && bind(sock, (struct sockaddr *)&me, sizeof(me)) == -1) {
			perror("bind");
			goto bail;
		}
	}

	clnt->sock = sock;
	clnt->call_stub = rpc_call_udp;

	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = server;

	if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
		perror("connect");
		goto bail;
	}

	goto done;
      bail:
	if (clnt) {
		free(clnt);
		clnt = NULL;
	}
      done:
	return clnt;
}

void client_free(struct client *c)
{
	if (c->sock != -1)
		close(c->sock);
	free(c);
}

int rpc_call(struct client *client, struct rpc *rpc)
{
	return client->call_stub(client, rpc);
}
