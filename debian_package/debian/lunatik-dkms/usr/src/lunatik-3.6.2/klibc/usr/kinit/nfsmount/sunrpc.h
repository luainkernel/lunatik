/*
 * open-coded SunRPC structures
 */
#ifndef NFSMOUNT_SUNRPC_H
#define NFSMOUNT_SUNRPC_H

#include <sys/types.h>
#include <inttypes.h>

#define SUNRPC_PORT	111
#define MOUNT_PORT	627

#define RPC_CALL	0
#define RPC_REPLY	1

#define PORTMAP_PROGRAM	100000
#define NLM_PROGRAM	100021

#define RPC_PMAP_PROGRAM	100000
#define RPC_PMAP_VERSION	2
#define RPC_PMAP_PORT		111

#define PMAP_PROC_NULL		0
#define PMAP_PROC_SET		1
#define PMAP_PROC_UNSET		2
#define PMAP_PROC_GETPORT	3
#define PMAP_PROC_DUMP		4

#define LAST_FRAG	0x80000000

#define REPLY_OK	0
#define REPLY_DENIED    1

#define SUCCESS		0
#define PROG_UNAVAIL	1
#define PROG_MISMATCH	2
#define PROC_UNAVAIL	3
#define GARBAGE_ARGS	4
#define SYSTEM_ERR	5

enum {
	AUTH_NULL,
	AUTH_UNIX,
};

struct rpc_auth {
	uint32_t flavor;
	uint32_t len;
	uint32_t body[];
};

struct rpc_udp_header {
	uint32_t xid;
	uint32_t msg_type;
};

struct rpc_header {
	uint32_t frag_hdr;
	struct rpc_udp_header udp;
};

struct rpc_call {
	struct rpc_header hdr;
	uint32_t rpc_vers;

	uint32_t program;
	uint32_t prog_vers;
	uint32_t proc;
	uint32_t cred_flavor;

	uint32_t cred_len;
	uint32_t vrf_flavor;
	uint32_t vrf_len;
};

struct rpc_reply {
	struct rpc_header hdr;
	uint32_t reply_state;
	uint32_t vrf_flavor;
	uint32_t vrf_len;
	uint32_t state;
};

struct rpc {
	struct rpc_call *call;
	size_t call_len;
	struct rpc_reply *reply;
	size_t reply_len;
};

struct client;

typedef int (*call_stub) (struct client *, struct rpc *);

struct client {
	int sock;
	call_stub call_stub;
};

#define CLI_RESVPORT	00000001

struct client *tcp_client(uint32_t server, uint16_t port, uint32_t flags);
struct client *udp_client(uint32_t server, uint16_t port, uint32_t flags);
void client_free(struct client *client);

int rpc_call(struct client *client, struct rpc *rpc);

uint32_t portmap(uint32_t server, uint32_t program, uint32_t version, uint32_t proto);

#endif /* NFSMOUNT_SUNRPC_H */
