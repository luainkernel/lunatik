/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* TLS handshakes performed by the userspace agent.
* A script hands a connected socket to `tlshd`, which negotiates the session,
* promotes the socket to the `tls` ULP and installs the keys itself: a script
* neither attaches the ULP nor keys the socket. The call blocks until the agent
* reports, so the runtime must be sleepable.
*
* Nothing else may read the socket while a handshake is on it: the agent holds a
* file for it and drives the negotiation with its own blocking reads.
*
* @module handshake
* @see socket
* @see socket.tls
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/completion.h>
#include <linux/file.h>
#include <linux/key.h>
#include <linux/net.h>
#include <net/handshake.h>
#include <net/sock.h>
#include <net/tcp_states.h>

#include <lunatik.h>

#include "luasocket.h"

typedef int (*luahandshake_hello_t)(const struct tls_handshake_args *args, gfp_t flags);

/* anon is the client's alone: the kernel publishes no anonymous server hello */
typedef struct {
	luahandshake_hello_t anon;
	luahandshake_hello_t x509;
	luahandshake_hello_t psk;
} luahandshake_hellos_t;

typedef struct {
	struct completion done;
	int status;
	key_serial_t peerid;
} luahandshake_t;

static void luahandshake_done(void *data, int status, key_serial_t peerid)
{
	luahandshake_t *handshake = (luahandshake_t *)data;

	handshake->status = status;
	handshake->peerid = peerid;
	complete(&handshake->done);
}

static int luahandshake_getfield(lua_State *L, int ix, const char *field, int type)
{
	int got = lua_getfield(L, ix, field);

	if (got != LUA_TNIL && got != type)
		luaL_error(L, "bad field '%s' (%s expected, got %s)", field,
			lua_typename(L, type), lua_typename(L, got));
	return got;
}

static lua_Integer luahandshake_optinteger(lua_State *L, int ix, const char *field,
	lua_Integer min, lua_Integer max)
{
	luahandshake_getfield(L, ix, field, LUA_TNUMBER);
	lua_Integer value = lua_tointeger(L, -1); /* an absent option reads as zero, the "none" each one spells */

	lunatik_checkbounds(L, ix, value, min, max);
	lua_pop(L, 1); /* field */
	return value;
}

/* key_serial_t is a signed 32-bit id: a KEY_SPEC_* keyring is negative */
#define luahandshake_optserial(L, ix, field)	\
	((key_serial_t)luahandshake_optinteger((L), (ix), (field), INT_MIN, INT_MAX))

static unsigned int luahandshake_peerids(lua_State *L, int ix, key_serial_t *peerids, unsigned int max)
{
	unsigned int i, n = (unsigned int)lua_rawlen(L, -1);

	luaL_argcheck(L, n <= max, ix, "too many peerids");
	for (i = 0; i < n; i++) {
		luaL_argcheck(L, lua_rawgeti(L, -1, i + 1) == LUA_TNUMBER, ix, "peerids holds a non-integer");
		lua_Integer serial = lua_tointeger(L, -1);

		lunatik_checkbounds(L, ix, serial, INT_MIN, INT_MAX);
		peerids[i] = (key_serial_t)serial;
		lua_pop(L, 1); /* peerid */
	}
	return n;
}

static luahandshake_hello_t luahandshake_checkanon(lua_State *L, int ix, const luahandshake_hellos_t *hellos)
{
	luaL_argcheck(L, hellos->anon != NULL, ix, "no anonymous server handshake");
	return hellos->anon;
}

static luahandshake_hello_t luahandshake_checkopts(lua_State *L, int ix,
	const luahandshake_hellos_t *hellos, struct tls_handshake_args *args)
{
	if (lua_isnoneornil(L, ix))
		return luahandshake_checkanon(L, ix, hellos);

	luaL_checktype(L, ix, LUA_TTABLE);
	args->ta_timeout_ms = (unsigned int)luahandshake_optinteger(L, ix, "timeout", 0, UINT_MAX);
	args->ta_keyring = luahandshake_optserial(L, ix, "keyring");
	args->ta_my_cert = luahandshake_optserial(L, ix, "cert");
	args->ta_my_privkey = luahandshake_optserial(L, ix, "privkey");
	/* stays on the stack: the peer name travels by pointer and is read when the agent accepts */
	args->ta_peername = luahandshake_getfield(L, ix, "peername", LUA_TSTRING) != LUA_TNIL ?
		lua_tostring(L, -1) : NULL;

	if (luahandshake_getfield(L, ix, "peerids", LUA_TTABLE) != LUA_TNIL) {
		luaL_argcheck(L, args->ta_my_cert == TLS_NO_CERT && args->ta_my_privkey == TLS_NO_PRIVKEY,
			ix, "peerids and cert name different handshakes");
		args->ta_num_peerids = luahandshake_peerids(L, ix, args->ta_my_peerids,
			ARRAY_SIZE(args->ta_my_peerids));
		lua_pop(L, 1); /* peerids */
		return hellos->psk;
	}
	lua_pop(L, 1); /* peerids */

	if (args->ta_my_cert == TLS_NO_CERT && args->ta_my_privkey == TLS_NO_PRIVKEY)
		return luahandshake_checkanon(L, ix, hellos);

	luaL_argcheck(L, args->ta_my_cert != TLS_NO_CERT && args->ta_my_privkey != TLS_NO_PRIVKEY,
		ix, "cert and privkey go together");
	return hellos->x509;
}

static int luahandshake_wait(struct sock *sk, luahandshake_t *handshake, unsigned int timeout)
{
	unsigned long timeout_jiffies = timeout != 0 ? msecs_to_jiffies(timeout) : MAX_SCHEDULE_TIMEOUT;
	long waited = wait_for_completion_interruptible_timeout(&handshake->done, timeout_jiffies);

	/* tls_handshake_done negates: the agent's errno arrives negative, the kernel's own -EIO positive */
	if (waited > 0)
		return -abs(handshake->status);
	if (!tls_handshake_cancel(sk))
		wait_for_completion(&handshake->done); /* the cancel lost the race and one callback is still owed */
	return waited == 0 ? -ETIMEDOUT : -EINTR;
}

static int luahandshake_submit(luahandshake_hello_t hello, const struct tls_handshake_args *args)
{
	if (args->ta_sock->sk->sk_state != TCP_ESTABLISHED)
		return -ENOTCONN;
	return hello(args, GFP_KERNEL); /* a negative return leaves no callback outstanding */
}

static int luahandshake_request(lua_State *L, const luahandshake_hellos_t *hellos)
{
	struct tls_handshake_args args = {0};
	luahandshake_t handshake = {0};

	lunatik_checkruntime(L, LUNATIK_OPT_NONE);
	/* the options are checked before the socket takes the file it then carries for good */
	luahandshake_hello_t hello = luahandshake_checkopts(L, 2, hellos, &args);
	struct socket *sock = luasocket_openfile(L, 1);

	init_completion(&handshake.done);
	args.ta_sock = sock;
	args.ta_done = luahandshake_done;
	args.ta_data = &handshake;
	int ret = luahandshake_submit(hello, &args);

	if (ret == 0)
		ret = luahandshake_wait(sock->sk, &handshake, args.ta_timeout_ms);
	fput(sock->file); /* the agent reaches the socket through sk->sk_socket, which a close NULLs */
	if (ret < 0)
		lunatik_throw(L, ret);

	lua_pushinteger(L, (lua_Integer)handshake.peerid);
	return 1;
}

static const luahandshake_hellos_t luahandshake_clienthellos = {
	.anon = tls_client_hello_anon,
	.x509 = tls_client_hello_x509,
	.psk = tls_client_hello_psk,
};

static const luahandshake_hellos_t luahandshake_serverhellos = {
	.x509 = tls_server_hello_x509,
	.psk = tls_server_hello_psk,
};

/***
* Asks the agent for a TLS handshake, as the client.
* Blocks until the agent reports, `timeout` elapses or the wait is interrupted.
* The arm follows the credentials: `peerids` asks for a pre-shared key, `cert`
* with `privkey` for x.509, and neither for an anonymous session.
*
* @function client
* @tparam socket sock a connected socket.
* @tparam[opt] table opts handshake options, every one of them optional:
*
*   - `peername` (string): the name to present to the peer, and the one whose
*     certificate the agent checks.
*   - `timeout` (integer): milliseconds to wait, and the deadline the agent is
*     given. Omitted, the wait is indefinite and the agent gets no deadline: a
*     `spawn` thread that waits this way cannot be stopped until the agent answers.
*   - `keyring` (integer): serial of the keyring the agent looks keys up in.
*   - `cert` (integer), `privkey` (integer): serials of this side's x.509
*     certificate and its private key. Both or neither.
*   - `peerids` (table): serials of this side's pre-shared key identities, at
*     most five. Selects the pre-shared key handshake, and excludes `cert`.
* @treturn integer the peer identity the session authenticated, `0` for a session
*   carrying none.
* @raise `ENOTCONN` when the socket is not connected, `ESRCH` when no agent is
*   listening, `EINVAL` when `peerids` is empty, which the kernel's pre-shared
*   key hello refuses before it submits, `EBUSY` for a second handshake on a
*   socket that already carried one, which the kernel keeps keyed to it until it
*   is closed, `ETIMEDOUT` when `timeout` elapses, `EINTR` when the wait is
*   interrupted, the errno the agent reported, `runtime context mismatch` from a
*   runtime that may not sleep, `bad field 'timeout' (number expected, got string)`
*   for an option of the wrong type, or a `bad argument #2` naming what it refused:
*   `peerids and cert name different handshakes`, `cert and privkey go together`,
*   `too many peerids`, `peerids holds a non-integer`, `out of bounds`.
* @usage
*   local peerid = handshake.client(sock, {peername = "example.com", timeout = 5000})
* @see socket.tls
*/
static int luahandshake_client(lua_State *L)
{
	return luahandshake_request(L, &luahandshake_clienthellos);
}

/***
* Asks the agent for a TLS handshake, as the server.
* Blocks the same way `client` does, and takes the same options, except that the
* credentials are not optional: the kernel publishes no anonymous server hello.
*
* @function server
* @tparam socket sock a connected socket.
* @tparam table opts handshake options, as `client` takes them, carrying either
*   `peerids` or `cert` with `privkey`.
* @treturn integer the peer identity the session authenticated, `0` for a session
*   carrying none.
* @raise `bad argument #2 ... no anonymous server handshake` when the options name
*   no credentials, and everything `client` raises.
* @usage
*   local peerid = handshake.server(conn, {cert = certserial, privkey = keyserial})
* @see client
*/
static int luahandshake_server(lua_State *L)
{
	return luahandshake_request(L, &luahandshake_serverhellos);
}

static const luaL_Reg luahandshake_lib[] = {
	{"client", luahandshake_client},
	{"server", luahandshake_server},
	{NULL, NULL}
};

LUNATIK_NEWLIB(handshake, luahandshake_lib, NULL);

static int __init luahandshake_init(void)
{
	return 0;
}

static void __exit luahandshake_exit(void)
{
}

module_init(luahandshake_init);
module_exit(luahandshake_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

