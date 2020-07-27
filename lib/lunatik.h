/*
 * Copyright (c) 2020 Matheus Rodrigues <matheussr61@gmail.com>
 * Copyright (C) 2017-2019  CUJO LLC
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef LUNATIK_H
#define LUNATIK_H

#include <sys/user.h>
#include <stdint.h>
#include <netlink/genl/genl.h>
#include "../netlink_common.h"
#include "../lunatik_conf.h"

enum callback_result {
    CB_SUCCESS,
    CB_ERROR,
    CB_LIST_EMPTY,
};

enum session_status {
    SESSION_FREE,
    SESSION_RECEIVING,
    SESSION_INIT_LIST,
};

struct lunatik_nl_state {
    struct lunatik_session *session;
    uint32_t maxalloc;
    uint32_t curralloc;
    char name[LUNATIK_NAME_MAXSIZE];
};

struct states_list {
    struct lunatik_nl_state *states;
    size_t list_size;
};

struct received_buffer {
	char *buffer;
	int cursor;
};

struct lunatik_session {
    struct nl_sock *sock;
    struct states_list states_list;
    struct received_buffer recv_buffer;
    enum session_status status;
    enum callback_result cb_result;
    int family;
    int fd;
    uint32_t pid;
};

#ifndef _UNUSED
struct nflua_data {
    int fd;
    uint32_t pid;
    uint32_t seqnum;
    char state[NFLUA_NAME_MAXSIZE];
    char buffer[NFLUA_PAYLOAD_MAXSIZE];
};
#endif /* _UNUSED */

static inline int lunatikS_getfd(const struct lunatik_session *session)
{
    return session->fd;
}

static inline int lunatikS_isopen(const struct lunatik_session *session)
{
    return session->fd >= 0;
}

int lunatikS_init(struct lunatik_session *session);

void lunatikS_close(struct lunatik_session *session);

int lunatikS_newstate(struct lunatik_session *session, struct lunatik_nl_state *s);

int lunatikS_closestate(struct lunatik_session *session, const char *name);

int lunatikS_dostring(struct lunatik_session *session, const char *state_name,
    const char *script, const char *script_name, size_t total_code_size);

int lunatikS_list(struct lunatik_session *session);

#ifndef _UNUSED
int nflua_control_receive(struct nflua_control *ctrl,
        struct nflua_response *nr, char *buffer);

static inline int nflua_data_getsock(const struct nflua_data *dch)
{
    return dch->fd;
}

static inline int nflua_data_getpid(const struct nflua_data *dch)
{
    return dch->pid;
}

static inline int nflua_data_is_open(const struct nflua_data *dch)
{
    return dch->fd >= 0;
}

int nflua_data_init(struct nflua_data *dch, uint32_t pid);

void nflua_data_close(struct nflua_data *dch);

int nflua_data_send(struct nflua_data *dch, const char *name,
        const char *payload, size_t len);

int nflua_data_receive(struct nflua_data *dch, char *state, char *buffer);
#endif /* _UNUSED */
#endif /* LUNATIK_H */
