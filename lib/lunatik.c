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

static int lunatik_family;

static struct nl_msg *prepare_message(int command, int flags)
{
	struct nl_msg *msg;

	if ((msg = nlmsg_alloc()) == NULL) {
		printf("Failed to allocate a new message\n");
		return NULL;
	}

	if ((genlmsg_put(msg, NL_AUTO_PORT, NL_AUTO_SEQ, lunatik_family,
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

static int send_simple_control_msg(struct lunatik_session *session, int command, int flags)
{
	struct nl_msg *msg;
	int err = -1;

	if ((msg = prepare_message(command, flags)) == NULL) {
		printf("Error preparing message\n");
		goto error;
	}

	if ((err = nl_send_auto(session->control_sock, msg)) < 0) {
		printf("Failed sending message to kernel\n");
		goto error;
	}

	nlmsg_free(msg);
	return 0;

error:
	nlmsg_free(msg);
	return err;
}

static int send_fragment(struct lunatik_nl_state *state, const char *original_script, int offset,
	const char *script_name, int flags)
{
	struct nl_msg *msg;
	char *fragment;
	int err = -1;
	if ((msg = prepare_message(EXECUTE_CODE, 0)) == NULL){
		nlmsg_free(msg);
		return err;
	}

	if ((fragment = malloc(sizeof(char) * LUNATIK_FRAGMENT_SIZE)) == NULL) {
		printf("Failed to allocate memory to code fragment\n");
		return -ENOMEM;
	}
	strncpy(fragment, original_script + (offset * LUNATIK_FRAGMENT_SIZE), LUNATIK_FRAGMENT_SIZE);

	NLA_PUT_STRING(msg, STATE_NAME, state->name);
	NLA_PUT_STRING(msg, CODE, fragment);

	if (offset == 0)
		NLA_PUT_U32(msg, SCRIPT_SIZE, strlen(original_script));

	if (flags & LUNATIK_DONE)
		NLA_PUT_STRING(msg, SCRIPT_NAME, script_name);

	NLA_PUT_U8(msg, FLAGS, flags);

	if ((err = nl_send_auto(state->control_sock, msg)) < 0) {
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

static int receive_session_op_result(struct lunatik_session *session){
	int ret;

	if ((ret = nl_recvmsgs_default(session->control_sock))) {
		printf("Failed to receive message from kernel: %s\n", nl_geterror(ret));
		return ret;
	}

	nl_wait_for_ack(session->control_sock);

	if (session->cb_result == CB_ERROR){
		session->cb_result = CB_EMPTY_RESULT;
		return -1;
	}

	return 0;
}

static int receive_state_op_result(struct lunatik_nl_state *state){
	int ret;

	if ((ret = nl_recvmsgs_default(state->control_sock))) {
		printf("Failed to receive message from kernel: %s\n", nl_geterror(ret));
		return ret;
	}

	nl_wait_for_ack(state->control_sock);

	if (state->cb_result == CB_ERROR){
		state->cb_result = CB_EMPTY_RESULT;
		return -1;
	}

	return 0;
}

int init_recv_datasocket_on_kernel(struct lunatik_nl_state *state)
{
	struct nl_msg *msg;
	int err = -1;

	if ((msg = prepare_message(DATA_INIT, 0)) == NULL) {
		printf("Error preparing message\n");
		goto error;
	}

	NLA_PUT_STRING(msg, STATE_NAME, state->name);

	if ((err = nl_send_auto(state->recv_datasock, msg)) < 0) {
		printf("Failed sending message to kernel\n");
		goto error;
	}

	nl_recvmsgs_default(state->recv_datasock);
	nl_wait_for_ack(state->recv_datasock);

	if (state->cb_result == CB_ERROR) {
		state->cb_result = CB_EMPTY_RESULT;
		goto error;
	}

	nlmsg_free(msg);

	return 0;

error:
	nlmsg_free(msg);
	return err;

nla_put_failure:
	printf("Failed to put attributes on to initialize data socket on kernel side\n");
	return err;
}

int lunatikS_newstate(struct lunatik_session *session, struct lunatik_nl_state *cmd)
{
	struct nl_msg *msg;
	int ret = -1;

	if ((msg = prepare_message(CREATE_STATE, 0)) == NULL)
		return ret;

	NLA_PUT_STRING(msg, STATE_NAME, cmd->name);
	NLA_PUT_U32(msg, MAX_ALLOC, cmd->maxalloc);

	if ((ret = nl_send_auto(session->control_sock, msg)) < 0) {
		printf("Failed to send message to kernel\n %s\n", nl_geterror(ret));
		return ret;
	}

	return receive_session_op_result(session);

nla_put_failure:
	printf("Failed to put attributes on message\n");
	return ret;
}

int lunatik_closestate(struct lunatik_nl_state *state)
{
	struct nl_msg *msg;
	int ret = -1;

	if ((msg = prepare_message(DESTROY_STATE, 0)) == NULL)
		return ret;

	NLA_PUT_STRING(msg, STATE_NAME, state->name);

	if ((ret = nl_send_auto(state->control_sock, msg)) < 0) {
		printf("Failed to send destroy message:\n\t%s\n", nl_geterror(ret));
		return ret;
	}

	ret = receive_state_op_result(state);

	nl_socket_free(state->send_datasock);
	nl_socket_free(state->recv_datasock);
	nl_socket_free(state->control_sock);

	return ret;

nla_put_failure:
	printf("Failed to put attributes on netlink message\n");
	return ret;
}

int lunatik_dostring(struct lunatik_nl_state *state,
    const char *script, const char *script_name, size_t total_code_size)
{
	int err = -1;
	int parts = 0;

	if (total_code_size <= LUNATIK_FRAGMENT_SIZE) {
		err = send_fragment(state, script, 0, script_name, LUNATIK_INIT | LUNATIK_DONE);
		if (err)
			return err;
	} else {
		parts = (total_code_size % LUNATIK_FRAGMENT_SIZE == 0) ?
			total_code_size / LUNATIK_FRAGMENT_SIZE :
			(total_code_size / LUNATIK_FRAGMENT_SIZE) + 1;

		for (int i = 0; i < parts - 1; i++) {
			if (i == 0)
				err = send_fragment(state, script, i, script_name, LUNATIK_INIT | LUNATIK_MULTI);
			else
				err = send_fragment(state, script, i, script_name, LUNATIK_MULTI);

			nl_wait_for_ack(state->control_sock);

			if (err)
				return err;
		}

		err = send_fragment(state, script, parts - 1, script_name, LUNATIK_DONE);
		if (err)
			return err;
	}

	return receive_state_op_result(state);
}

int lunatikS_list(struct lunatik_session *session)
{
	int err = -1;

	if ((err = send_simple_control_msg(session, LIST_STATES, 0)))
		return err;

	nl_recvmsgs_default(session->control_sock);
	nl_wait_for_ack(session->control_sock);

	if (session->cb_result == CB_ERROR)
		return -1;

	while (session->status == SESSION_RECEIVING) {
		send_simple_control_msg(session, LIST_STATES, 0);
		nl_recvmsgs_default(session->control_sock);
		nl_wait_for_ack(session->control_sock);
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

static int send_data_cb_handler(struct nl_msg *msg, void *arg)
{
	struct nlmsghdr *nh = nlmsg_hdr(msg);
	struct genlmsghdr *gnlh = genlmsg_hdr(nh);
	struct nlattr * attrs_tb[ATTRS_COUNT + 1];
	struct lunatik_nl_state *state = (struct lunatik_nl_state *)arg;

	if (nla_parse(attrs_tb, ATTRS_COUNT, genlmsg_attrdata(gnlh, 0),
              genlmsg_attrlen(gnlh, 0), NULL))
	{
		printf("Error parsing attributes\n");
		state->cb_result = CB_ERROR;
		return NL_OK;
	}

	if (attrs_tb[OP_SUCESS] && nla_get_u8(attrs_tb[OP_SUCESS])) {
		state->cb_result = CB_SUCCESS;
	} else if (attrs_tb[OP_ERROR] && nla_get_u8(attrs_tb[OP_ERROR])) {
		state->cb_result = CB_ERROR;
	}

	return NL_OK;
}

int init_socket(struct nl_sock**);

static int get_state_handler(struct lunatik_session *session, struct nlattr **attrs_tb)
{
	char *name;

	if (!(attrs_tb[STATE_NAME] || attrs_tb[CURR_ALLOC] || attrs_tb[MAX_ALLOC])) {
		printf("Some attributes are missing\n");
		return -1;
	}

	name = nla_get_string(attrs_tb[STATE_NAME]);

	strcpy(session->state_holder.name, name);
	session->state_holder.curralloc = nla_get_u32(attrs_tb[CURR_ALLOC]);
	session->state_holder.maxalloc  = nla_get_u32(attrs_tb[MAX_ALLOC]);
	session->state_holder.session   = session;

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
			session->cb_result = CB_LIST_EMPTY;
			return NL_OK;
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
			session->cb_result = CB_ERROR;

		break;
	case GET_STATE:
		if (attrs_tb[STATE_NOT_FOUND]) {
			session->cb_result = CB_STATE_NOT_FOUND;
			return NL_OK;
		}

		if (attrs_tb[OP_ERROR]) {
			session->cb_result = CB_ERROR;
			return NL_OK;
		}

		if (get_state_handler(session, attrs_tb))
			session->cb_result = CB_ERROR;

		break;
	default:
		break;
	}

	return NL_OK;
}

static int response_state_handler(struct nl_msg *msg, void *arg)
{
	struct nlmsghdr *nh = nlmsg_hdr(msg);
	struct genlmsghdr *gnlh = genlmsg_hdr(nh);
	struct nlattr * attrs_tb[ATTRS_COUNT + 1];
	struct lunatik_nl_state *state = (struct lunatik_nl_state *)arg;

	if (nla_parse(attrs_tb, ATTRS_COUNT, genlmsg_attrdata(gnlh, 0),
              genlmsg_attrlen(gnlh, 0), NULL))
	{
		printf("Error parsing attributes\n");
		state->cb_result = CB_ERROR;
		return NL_OK;
	}

	if (attrs_tb[OP_SUCESS] && nla_get_u8(attrs_tb[OP_SUCESS])) {
		state->cb_result = CB_SUCCESS;
	} else if (attrs_tb[OP_ERROR] && nla_get_u8(attrs_tb[OP_ERROR])) {
		state->cb_result = CB_ERROR;
	}

	return NL_OK;
}

static int init_data_buffer(struct data_buffer *data_buffer, size_t size);

static int data_handler(struct nl_msg *msg, void *arg)
{
	struct nlmsghdr *nh = nlmsg_hdr(msg);
	struct genlmsghdr *gnlh = genlmsg_hdr(nh);
	struct lunatik_nl_state *state = (struct lunatik_nl_state *) arg;
	struct data_buffer *data_buffer = &state->data_buffer;
	struct nlattr *attrs_tb[ATTRS_COUNT + 1];
	char *payload;
	size_t payload_size;
	int err;

	if (nla_parse(attrs_tb, ATTRS_COUNT, genlmsg_attrdata(gnlh, 0),
              genlmsg_attrlen(gnlh, 0), NULL))
	{
		printf("Error parsing attributes\n");
		state->cb_result = CB_ERROR;
		return NL_OK;
	}

	if (attrs_tb[OP_SUCESS]) {
		state->cb_result = CB_SUCCESS;
		return NL_OK;
	}

	if (attrs_tb[OP_ERROR]) {
		state->cb_result = CB_ERROR;
		return NL_OK;
	}

	if (attrs_tb[LUNATIK_DATA] && attrs_tb[LUNATIK_DATA_LEN]) {
		payload = nla_get_string(attrs_tb[LUNATIK_DATA]);
		payload_size = nla_get_u32(attrs_tb[LUNATIK_DATA_LEN]);

		err = init_data_buffer(&state->data_buffer, payload_size);
		if (err) {
			state->cb_result = CB_ERROR;
			return NL_OK;
		}

		memcpy(data_buffer->buffer, payload, payload_size);
		data_buffer->size = payload_size;
	}

	return NL_OK;
}

int init_socket(struct nl_sock **socket)
{
	int err = -1;
	if ((*socket = nl_socket_alloc()) == NULL)
		return err;

	if ((err = genl_connect(*socket)))
		return err;

	if ((lunatik_family = genl_ctrl_resolve(*socket, LUNATIK_FAMILY)) < 0)
		return lunatik_family;

	return 0;
}

int lunatikS_init(struct lunatik_session *session)
{
	int err = -1;

	if (session == NULL)
		return -EINVAL;

	if ((err = init_socket(&session->control_sock))) {
		printf("Failed to initialize control socket\n");
		nl_socket_free(session->control_sock);
		return err;
	}

	nl_socket_modify_cb(session->control_sock, NL_CB_MSG_IN, NL_CB_CUSTOM, response_handler, session);
	session->control_fd = nl_socket_get_fd(session->control_sock);

	return 0;
}

void lunatikS_close(struct lunatik_session *session)
{
	if (session != NULL){
		nl_socket_free(session->control_sock);
		session->control_fd = -1;
	}
}

int lunatik_datasend(struct lunatik_nl_state *state, const char *payload, size_t len)
{
	struct nl_msg *msg = prepare_message(DATA, 0);
	int err = 0;

	if (msg == NULL)
		return -1;

	if (state->send_datasock == NULL) {
		printf("There is no socket available to send a message from this state, did you initialize the data for this state?\n");
		return -1;
	}

	NLA_PUT_STRING(msg, LUNATIK_DATA, payload);
	NLA_PUT_STRING(msg, STATE_NAME, state->name);
	NLA_PUT_U32(msg, LUNATIK_DATA_LEN, len);

	if ((err = nl_send_auto(state->send_datasock, msg)) < 0) {
		printf("Failed sending message to kernel\n");
		nlmsg_free(msg);
		return err;
	}

	nl_recvmsgs_default(state->send_datasock);
	nl_wait_for_ack(state->send_datasock);
	nlmsg_free(msg);

	if (state->cb_result == CB_ERROR) {
		state->cb_result = CB_EMPTY_RESULT;
		return -1;
	}

	return 0;

nla_put_failure:
	printf("Failure to put attributes to data send operation\n");
	nlmsg_free(msg);
	return -1;
}

static int init_data_buffer(struct data_buffer *data_buffer, size_t size)
{
	if ((data_buffer->buffer = malloc(size)) == NULL) {
		printf("Failed to allocate memory to data buffer\n");
		return -1;
	}
	memset(data_buffer->buffer, 0, size);
	data_buffer->size = size;
	return 0;
}

void release_data_buffer(struct data_buffer *data_buffer)
{
	free(data_buffer->buffer);
	data_buffer->size = 0;
}

int lunatik_receive(struct lunatik_nl_state *state)
{
	int err = 0;

	nl_recvmsgs_default(state->recv_datasock);

	if (state->cb_result == CB_ERROR) {
		state->cb_result = CB_EMPTY_RESULT;
		err = -1;
	}

	return err;
}

static int lunatik_initdata(struct lunatik_nl_state *state)
{
	int ret = 0;

	if ((ret = init_socket(&state->send_datasock))) {
		printf("Failed to initialize the send socket\n");
		nl_socket_free(state->send_datasock);
		return ret;
	}

	if ((ret = init_socket(&state->recv_datasock))) {
		printf("Failed to initialize the recv socket\n");
		nl_socket_free(state->recv_datasock);
		return ret;
	}

	if ((ret = init_recv_datasocket_on_kernel(state))) {
		printf("Failed to initialize receive socket on kernel\n");
		nl_socket_free(state->recv_datasock);
		return ret;
	}

	nl_socket_modify_cb(state->send_datasock, NL_CB_MSG_IN, NL_CB_CUSTOM, send_data_cb_handler, state);
	nl_socket_modify_cb(state->recv_datasock, NL_CB_MSG_IN, NL_CB_CUSTOM, data_handler, state);
	nl_socket_disable_seq_check(state->recv_datasock);
	nl_socket_disable_auto_ack(state->recv_datasock);

	return 0;
}

struct lunatik_nl_state *lunatikS_getstate(struct lunatik_session *session, const char *name)
{
	struct nl_msg *msg = prepare_message(GET_STATE, 0);

	NLA_PUT_STRING(msg, STATE_NAME, name);

	if (nl_send_auto(session->control_sock, msg) < 0) {
		printf("Failed to send message to kernel\n");
		return NULL;
	}

	if (receive_session_op_result(session))
		return NULL;

	if ((session->cb_result == CB_STATE_NOT_FOUND) || (session->cb_result == CB_ERROR)) {
		session->cb_result = CB_EMPTY_RESULT;
		return NULL;
	}

	return &session->state_holder;

nla_put_failure:
	printf("Failed to put attributes on netlink message\n");
	return NULL;
}

int lunatik_initstate(struct lunatik_nl_state *state)
{
	int err;

	if ((err = lunatik_initdata(state))) {
		return err;
	}

	if ((err = init_socket(&state->control_sock))) {
		printf("Failed to initialize the control socket for state %s\n", state->name);
		nl_socket_free(state->control_sock);
		return err;
	}

	nl_socket_modify_cb(state->control_sock, NL_CB_MSG_IN, NL_CB_CUSTOM, response_state_handler, state);

	return 0;
}

