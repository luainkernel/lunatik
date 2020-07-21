/*
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

#ifndef NFLUA_H
#define NFLUA_H

#include <sys/user.h>
#include <stdint.h>
#include <netlink_common.h>

enum nflua_control_state {
    NFLUA_LINK_READY,
    NFLUA_SENDING_REQUEST,
    NFLUA_PENDING_REPLY,
    NFLUA_RECEIVING_REPLY,
    NFLUA_PROTOCOL_OUTOFSYNC,
    NFLUA_SOCKET_CLOSED,
};

struct nflua_response {
    uint32_t type;
    uint32_t count;
    uint32_t total_size;
};

struct nflua_control {
    int fd;
    uint32_t pid;
    uint32_t seqnum;
    int currfrag;
    enum nflua_control_state state;
    uint8_t buffer[NFLUA_PAYLOAD_MAXSIZE];
};

struct nflua_data {
    int fd;
    uint32_t pid;
    uint32_t seqnum;
    char state[NFLUA_NAME_MAXSIZE];
    char buffer[NFLUA_PAYLOAD_MAXSIZE];
};

static inline int nflua_control_getsock(const struct nflua_control *ctrl)
{
    return ctrl->fd;
}

static inline int nflua_control_getstate(const struct nflua_control *ctrl)
{
    return ctrl->state;
}

static inline int nflua_control_getpid(const struct nflua_control *ctrl)
{
    return ctrl->pid;
}

static inline int nflua_control_is_open(const struct nflua_control *ctrl)
{
    return ctrl->fd >= 0;
}

int nflua_control_init(struct nflua_control *ctrl, uint32_t pid);

void nflua_control_close(struct nflua_control *ctrl);

int nflua_control_create(struct nflua_control *ctrl, struct nflua_nl_state *);

int nflua_control_destroy(struct nflua_control *ctrl, const char *name);

int nflua_control_execute(struct nflua_control *ctrl, const char *name,
        const char *scriptname, const char *payload, size_t total);

int nflua_control_list(struct nflua_control *ctrl);

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

#endif /* NFLUA_H */
