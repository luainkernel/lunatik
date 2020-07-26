/*
 * Copyright (c) 2020 Matheus Rodrigues <matheussr61@gmail.com>
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

#include <stdlib.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

#include <netlink/netlink.h>
#include <netlink/genl/ctrl.h>
#include <netlink/genl/genl.h>
#include <linux/netlink.h>

#include "lunatik.h"

#define MIN(x,y) ((x) < (y) ? (x) : (y))

static struct nl_msg *prepare_message(struct lunatik_session *session, int command, int flags)
{
	struct nl_msg *msg;

	if ((msg = nlmsg_alloc()) == NULL) {
		printf("Failed to allocate a new message\n");
		return NULL;
	}

	if ((genlmsg_put(msg, NL_AUTO_PORT, NL_AUTO_SEQ, session->family,
					0, 0, command, LUNATIK_NLVERSION)) == NULL) {
		printf("Failed to put generic netlink message header\n");
		return NULL;
	}

	NLA_PUT_U8(msg, FLAGS, flags);

	return msg;

nla_put_failure:
	printf("Failed to put attributes preparing the message\n");
	return NULL;
}

static int send_simple_msg(struct lunatik_session *session, int command, int flags)
{
	struct nl_msg *msg;
	int err = -1;

	if ((msg = prepare_message(session, command, flags)) == NULL) {
		printf("Error preparing message\n");
		goto error;
	}

	if ((err = nl_send_auto(session->sock, msg)) < 0) {
		printf("Failed sending message to kernel\n");
		goto error;
	}

	nlmsg_free(msg);
	return 0;

error:
	nlmsg_free(msg);
	return err;
}

static int send_fragment(struct lunatik_session *session, const char *original_script, int offset,
	const char *state_name, const char *script_name, int flags)
{
	struct nl_msg *msg;
	char *fragment;
	int err = -1;
	if ((msg = prepare_message(session, EXECUTE_CODE, 0)) == NULL){
		nlmsg_free(msg);
		return err;
	}

	if ((fragment = malloc(sizeof(char) * LUNATIK_FRAGMENT_SIZE)) == NULL) {
		printf("Failed to allocate memory to code fragment\n");
		return -ENOMEM;
	}
	strncpy(fragment, original_script + (offset * LUNATIK_FRAGMENT_SIZE), LUNATIK_FRAGMENT_SIZE);

	NLA_PUT_STRING(msg, STATE_NAME, state_name);
	NLA_PUT_STRING(msg, CODE, fragment);

	if (offset == 0)
		NLA_PUT_U32(msg, SCRIPT_SIZE, strlen(original_script));

	if (flags & LUNATIK_DONE)
		NLA_PUT_STRING(msg, SCRIPT_NAME, script_name);

	NLA_PUT_U8(msg, FLAGS, flags);

	
	if ((err = nl_send_auto(session->sock, msg)) < 0) {
		printf("Failed to send fragment\n %s\n", nl_geterror(err));
		nlmsg_free(msg);
		return err;
	}

	nlmsg_free(msg);

	return 0;

nla_put_failure:
	printf("Failed putting attributes on the message\n");
	free(fragment);
	return err;
}

static int receive_op_result(struct lunatik_session *session){
	int ret;

	if ((ret = nl_recvmsgs_default(session->sock))) {
		printf("Failed to receive message from kernel: %s\n", nl_geterror(ret));
		return ret;
	}

	nl_wait_for_ack(session->sock);

	if (session->cb_result == CB_ERROR)
		return -1;

	return 0;
}

int lunatikS_create(struct lunatik_session *session, struct lunatik_nl_state *cmd)
{
	struct nl_msg *msg;
	int ret = -1;

	if ((msg = prepare_message(session, CREATE_STATE, 0)) == NULL)
		return ret;

	NLA_PUT_STRING(msg, STATE_NAME, cmd->name);
	NLA_PUT_U32(msg, MAX_ALLOC, cmd->maxalloc);

	if ((ret = nl_send_auto(session->sock, msg)) < 0) {
		printf("Failed to send message to kernel\n %s\n", nl_geterror(ret));
		return ret;
	}

	return receive_op_result(session);

nla_put_failure:
	printf("Failed to put attributes on message\n");
	return ret;
}

int lunatikS_destroy(struct lunatik_session *session, const char *name)
{
	struct nl_msg *msg;
	int ret = -1;

	if ((msg = prepare_message(session, DESTROY_STATE, 0)) == NULL)
		return ret;

	NLA_PUT_STRING(msg, STATE_NAME, name);

	if ((ret = nl_send_auto(session->sock, msg)) < 0) {
		printf("Failed to send destroy message:\n %s\n", nl_geterror(ret));
		return ret;
	}

	return receive_op_result(session);

nla_put_failure:
	printf("Failed to put attributes on netlink message\n");
	return ret;
}

int lunatikS_dostring(struct lunatik_session *session, const char *state_name,
    const char *script, const char *script_name, size_t total_code_size)
{
	int err = -1;
	int parts = 0;

	if (total_code_size <= LUNATIK_FRAGMENT_SIZE) {
		err = send_fragment(session, script, 0, state_name, script_name, LUNATIK_INIT | LUNATIK_DONE);
		if (err)
			return err;
	} else {
		parts = (total_code_size % LUNATIK_FRAGMENT_SIZE == 0) ?
			total_code_size / LUNATIK_FRAGMENT_SIZE :
			(total_code_size / LUNATIK_FRAGMENT_SIZE) + 1;

		for (int i = 0; i < parts - 1; i++) {
			if (i == 0)
				err = send_fragment(session, script, i, state_name, script_name, LUNATIK_INIT | LUNATIK_MULTI);
			else
				err = send_fragment(session, script, i, state_name, script_name, LUNATIK_MULTI);

			nl_wait_for_ack(session->sock);

			if (err)
				return err;
		}

		err = send_fragment(session, script, parts - 1, state_name, script_name, LUNATIK_DONE);
		if (err)
			return err;
	}

	return receive_op_result(session);
}

int lunatikS_list(struct lunatik_session *session)
{
	int err = -1;

	if ((err = send_simple_msg(session, LIST_STATES, 0)))
		return err;

	nl_recvmsgs_default(session->sock);
	nl_wait_for_ack(session->sock);

	if (session->cb_result == CB_ERROR)
		return -1;

	while (session->status == SESSION_RECEIVING) {
		send_simple_msg(session, LIST_STATES, 0);
		nl_recvmsgs_default(session->sock);
		nl_wait_for_ack(session->sock);
	}

	return 0;
}

static int parse_states_list(struct lunatik_session *session)
{
	struct lunatik_nl_state *states;
	char *ptr;
	char *buffer;
	int states_cursor = 0;

	buffer = (session->recv_buffer).buffer;

	states = (session->states_list).states;
	ptr = strtok(buffer, "#");
	while(ptr != NULL) {
		strcpy(states[states_cursor].name, ptr);
		ptr = strtok(NULL, "#");
		states[states_cursor].curralloc = atoi(ptr);
		ptr = strtok(NULL, "#");
		states[states_cursor].maxalloc = atoi(ptr);
		ptr = strtok(NULL, "#");
		states_cursor++;
	}
	return 0;
}

static int init_states_list(struct lunatik_session *session, struct nlattr **attrs)
{
	struct states_list *states_list;
	int states_count;

	states_list = &session->states_list;

	if (attrs[STATES_COUNT]) {
		states_count = nla_get_u32(attrs[STATES_COUNT]);
	} else {
		printf("Failed to initialize the states list, states count is missing\n");
		return -1;
	}

	states_list->states = malloc(sizeof(struct lunatik_nl_state) * states_count);

	if (states_list->states == NULL) {
		printf("Failed to allocate memory to store states information\n");
		return -ENOMEM;
	}
	states_list->list_size = states_count;
	return 0;
}

static int init_recv_buffer(struct lunatik_session *session, struct nlattr **attrs)
{
	struct received_buffer *recv_buffer;
	int parts;
	
	recv_buffer = &session->recv_buffer;

	if (attrs[PARTS]) {
		parts = nla_get_u32(attrs[PARTS]);
	} else {
		printf("Failed to initialize the recv buffer, states count is missing\n");
		return -1;
	}

	recv_buffer->buffer = malloc(LUNATIK_FRAGMENT_SIZE * parts);
	if (recv_buffer->buffer == NULL) {
		printf("Failed to allocate memory to received messages buffer\n");
		return -ENOMEM;
	}

	recv_buffer->cursor = 0;
	return 0;
}

static int append_recv_buffer(struct lunatik_session *session, struct nlattr **attrs)
{
	struct received_buffer *recv_buffer;
	char *fragment;

	recv_buffer = &session->recv_buffer;

	if (attrs[STATES_LIST]) {
		fragment = nla_get_string(attrs[STATES_LIST]);
	} else {
		printf("Failed to get fragment from states list, attribute is missing\n");
		return -1;
	}

	strncpy(recv_buffer->buffer + (LUNATIK_FRAGMENT_SIZE * recv_buffer->cursor),
			fragment, LUNATIK_FRAGMENT_SIZE);

	recv_buffer->cursor++;
	return 0;
}

static int response_handler(struct nl_msg *msg, void *arg)
{
	struct nlmsghdr *nh = nlmsg_hdr(msg);
	struct genlmsghdr *gnlh = genlmsg_hdr(nh);
	struct lunatik_session *session = (struct lunatik_session *) arg;
	struct nlattr * attrs_tb[ATTRS_COUNT + 1];
	uint8_t flags = 0;
	int err = 0;


	if (nla_parse(attrs_tb, ATTRS_COUNT, genlmsg_attrdata(gnlh, 0),
              genlmsg_attrlen(gnlh, 0), NULL))
	{
		printf("Error parsing attributes\n");
		session->cb_result = CB_ERROR;
		return NL_OK;
	}
	switch (gnlh->cmd)
	{
	case CREATE_STATE:
	case DESTROY_STATE:
	case EXECUTE_CODE:
		if (attrs_tb[OP_SUCESS] && nla_get_u8(attrs_tb[OP_SUCESS])) {
			session->cb_result = CB_SUCCESS;
		} else if (attrs_tb[OP_ERROR] && nla_get_u8(attrs_tb[OP_ERROR])) {
			session->cb_result = CB_ERROR;
		}
		break;
	case LIST_STATES:

		if (attrs_tb[STATES_LIST_EMPTY]) {
			session->states_list.list_size = 0;
			session->states_list.states = NULL;
			return 0;
		}

		if (attrs_tb[FLAGS]) {
			flags = nla_get_u8(attrs_tb[FLAGS]);
		}

		if (flags & LUNATIK_INIT) {
			err = init_states_list(session, attrs_tb);
			err = init_recv_buffer(session, attrs_tb);
			session->status = SESSION_RECEIVING;
		}

		if (flags & LUNATIK_DONE) {
			err = append_recv_buffer(session, attrs_tb);
			err = parse_states_list(session);
			session->status = SESSION_FREE;
			free(session->recv_buffer.buffer);
			session->recv_buffer.cursor = 0;
		}

		if (flags & LUNATIK_MULTI) {
			err = append_recv_buffer(session, attrs_tb);
		}

		if (err)
			session->cb_result = OP_ERROR;

		break;
	default:
		break;
	}

	return NL_OK;
}

int lunatikS_init(struct lunatik_session *session)
{
	int err = -1;

	if (session == NULL)
		return -EINVAL;

	if ((session->sock = nl_socket_alloc()) == NULL)
		return err;

	if ((err = genl_connect(session->sock)))
		return err;

	if ((session->family = genl_ctrl_resolve(session->sock, LUNATIK_FAMILY)) < 0)
		return err;

	nl_socket_modify_cb(session->sock, NL_CB_MSG_IN, NL_CB_CUSTOM, response_handler, session);
	session->fd = nl_socket_get_fd(session->sock);

	return 0;
}

void lunatikS_end(struct lunatik_session *session)
{
	if (session != NULL){
		nl_socket_free(session->sock);
		session->fd = -1;
	}
}
