/*
 * Copyright (C) 2020  Matheus Rodrigues <matheussr61@gmail.com>
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

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/types.h>
#include <linux/kernel.h>
#include <linux/random.h>
#include <linux/rculist.h>
#include <linux/slab.h>
#include <linux/hashtable.h>
#include <linux/jhash.h>
#include <linux/netlink.h>
#include <net/sock.h>

#include <lmemlib.h>

#include "luautil.h"
#include "lunatik.h"
#include "netlink_common.h"

#define DATA_RECV_FUNC	("receive_callback")

struct lunatik_nl_state {
	char name[LUNATIK_NAME_MAXSIZE];
	size_t maxalloc;
	size_t curralloc;
};

extern struct lunatik_instance *lunatik_pernet(struct net *net);

static int lunatikN_newstate(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_dostring(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_close(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_list(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_data(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_datainit(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_sendstate(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_getcurralloc(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_putstate(struct sk_buff *buff, struct genl_info *info);

struct nla_policy lunatik_policy[ATTRS_COUNT] = {
	[STATE_NAME]  = { .type = NLA_STRING },
	[CODE]	      = { .type = NLA_STRING },
	[SCRIPT_NAME] = { .type = NLA_STRING },
	[STATES_LIST] = { .type = NLA_STRING },
	[LUNATIK_DATA]= { .type = NLA_STRING },
	[LUNATIK_DATA_LEN] = { .type = NLA_U32},
	[SCRIPT_SIZE] = { .type = NLA_U32 },
	[MAX_ALLOC]   = { .type = NLA_U32 },
	[CURR_ALLOC]  = { .type = NLA_U32},
	[FLAGS]       = { .type = NLA_U8 },
	[OP_SUCESS]   = { .type = NLA_U8 },
	[OP_ERROR]    = { .type = NLA_U8 },
};

static const struct genl_ops l_ops[] = {
	{
		.cmd    = CREATE_STATE,
		.doit   = lunatikN_newstate,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		/*Before kernel 5.2.0, each operation has its own policy*/
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = EXECUTE_CODE,
		.doit   = lunatikN_dostring,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = DESTROY_STATE,
		.doit   = lunatikN_close,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = LIST_STATES,
		.doit   = lunatikN_list,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = DATA,
		.doit   = lunatikN_data,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = DATA_INIT,
		.doit   = lunatikN_datainit,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = GET_STATE,
		.doit   = lunatikN_sendstate,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = GET_CURRALLOC,
		.doit   = lunatikN_getcurralloc,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = PUT_STATE,
		.doit   = lunatikN_putstate,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		.policy = lunatik_policy
#endif
	}

};

struct genl_family lunatik_family = {
	.name 	 = LUNATIK_FAMILY,
	.version = LUNATIK_NLVERSION,
	.maxattr = ATTRS_MAX,
	.netnsok = true,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,2,0)
	.policy  = lunatik_policy,
#endif
	.module  = THIS_MODULE,
	.ops     = l_ops,
	.n_ops   = ARRAY_SIZE(l_ops),
};

static void fill_states_list(char *buffer, struct lunatik_instance *instance)
{
	struct lunatik_state *state;
	int bucket;
	int counter = 0;
	int states_count = atomic_read(&instance->states_count);

	hash_for_each_rcu(instance->states_table, bucket, state, node) {
		buffer += sprintf(buffer, "%s#", state->name);
		buffer += sprintf(buffer, "%ld#", state->curralloc);
		if (counter == states_count - 1)
			buffer += sprintf(buffer, "%ld", state->maxalloc);
		else
			buffer += sprintf(buffer, "%ld#", state->maxalloc);
		counter++;
	}
}

static void reply_with(int reply, int command, struct genl_info *info)
{
	struct sk_buff *obuff;
	void *msg_head;

	if ((obuff = genlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating message to an reply\n");
		return;
	}

	if ((msg_head = genlmsg_put_reply(obuff, info, &lunatik_family, 0, command)) == NULL) {
		pr_err("Failed to put generic netlink header\n");
		return;
	}

	if (nla_put_u8(obuff, reply, 1)) {
		pr_err("Failed to put attributes on socket buffer\n");
		return;
	}

	genlmsg_end(obuff, msg_head);

	if (genlmsg_reply(obuff, info) < 0) {
		pr_err("Failed to send message to user space\n");
		return;
	}

	pr_debug("Message sent to user space\n");
}

static void send_states_list(char *buffer, int flags, struct genl_info *info)
{
	struct sk_buff *obuff;
	void *msg_head;

	if ((obuff = genlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating message to an reply\n");
		return;
	}

	if ((msg_head = genlmsg_put_reply(obuff, info, &lunatik_family, 0, LIST_STATES)) == NULL) {
		pr_err("Failed to put generic netlink header\n");
		return;
	}

	if (nla_put_string(obuff, STATES_LIST, buffer)) {
		pr_err("Failed to put attributes on socket buffer\n");
		return;
	}

	if (nla_put_u8(obuff, FLAGS, flags)) {
		pr_err("Failed to put attributes on socket buffer\n");
		return;
	}

	genlmsg_end(obuff, msg_head);

	if (genlmsg_reply(obuff, info) < 0) {
		pr_err("Failed to send message to user space\n");
		return;
	}

	pr_debug("Message sent to user space\n");
}

static int lunatikN_newstate(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_instance *instance;
	struct lunatik_state *s;
	char *state_name;
	u32 *max_alloc;

	pr_debug("Received a CREATE_STATE message\n");

	instance = lunatik_pernet(genl_info_net(info));
	state_name = (char *)nla_data(info->attrs[STATE_NAME]);
	max_alloc = (u32 *)nla_data(info->attrs[MAX_ALLOC]);

	s = lunatik_netnewstate(state_name, *max_alloc, genl_info_net(info));

	if (s == NULL)
		goto error;

	if (s->inuse)
		goto error;

	s->instance = *instance;
	reply_with(OP_SUCESS, CREATE_STATE, info);
	s->inuse = true;

	return 0;

error:
	reply_with(OP_ERROR, CREATE_STATE, info);
	return 0;
}

static void init_codebuffer(lunatik_State *s, struct genl_info *info)
{
	s->scriptsize = *((u32*)nla_data(info->attrs[SCRIPT_SIZE]));

	if ((s->code_buffer = kmalloc(s->scriptsize, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating memory to code buffer\n");
		reply_with(OP_ERROR, EXECUTE_CODE, info);
	}

	s->buffer_offset = 0;
}

static void add_fragtostate(char *fragment, lunatik_State *s)
{
	strncpy(s->code_buffer + (s->buffer_offset * LUNATIK_FRAGMENT_SIZE),
					fragment, LUNATIK_FRAGMENT_SIZE);
	s->buffer_offset++;
}

static int dostring(char *code, lunatik_State *s, const char *script_name)
{
	int err = 0;
	int base;
	spin_lock_bh(&s->lock);

	if (!lunatik_getstate(s)) {
		pr_err("Failed to get state\n");
		err = -1;
		goto out;
	}

	base = lua_gettop(s->L);
	if ((err = luaU_dostring(s->L, code, s->scriptsize, script_name))) {
		pr_err("%s\n", lua_tostring(s->L, -1));
	}

	lunatik_putstate(s);
	lua_settop(s->L, base);

out:
	kfree(s->code_buffer);
	spin_unlock_bh(&s->lock);
	return err;
}

static int lunatikN_dostring(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_state *s;
	const char *script_name;
	char *fragment;
	char *state_name;
	int err;
	u8 flags;

	pr_debug("Received a EXECUTE_CODE message\n");

	state_name = (char *)nla_data(info->attrs[STATE_NAME]);
	fragment = (char *)nla_data(info->attrs[CODE]);
	flags = *((u8*)nla_data(info->attrs[FLAGS]));

	if ((s = lunatik_netstatelookup(state_name, genl_info_net(info))) == NULL) {
		pr_err("Error finding klua state\n");
		reply_with(OP_ERROR, EXECUTE_CODE, info);
		return 0;
	}

	if (flags & LUNATIK_INIT) {
		init_codebuffer(s, info);
	}

	if (flags & LUNATIK_MULTI) {
		add_fragtostate(fragment, s);
	}

	if (flags & LUNATIK_DONE){
		strcpy(s->code_buffer, fragment);
		script_name = nla_data(info->attrs[SCRIPT_NAME]);
		err = dostring(s->code_buffer, s, script_name);
		err ? reply_with(OP_ERROR, EXECUTE_CODE, info) : reply_with(OP_SUCESS, EXECUTE_CODE, info);
	}

	return 0;
}

static int lunatikN_close(struct sk_buff *buff, struct genl_info *info)
{
	char *state_name;

	state_name = (char *)nla_data(info->attrs[STATE_NAME]);

	pr_debug("Received a DESTROY_STATE command\n");

	if (lunatik_netclosestate(state_name, genl_info_net(info)))
		reply_with(OP_ERROR, DESTROY_STATE, info);
	else
		reply_with(OP_SUCESS, DESTROY_STATE, info);

	return 0;
}

static void send_init_information(int parts, int states_count, struct genl_info *info)
{
	struct sk_buff *obuff;
	void *msg_head;

	if ((obuff = genlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating message to an reply\n");
		return;
	}

	if ((msg_head = genlmsg_put_reply(obuff, info, &lunatik_family, 0, LIST_STATES)) == NULL) {
		pr_err("Failed to put generic netlink header\n");
		return;
	}

	if (nla_put_u32(obuff, STATES_COUNT, states_count) || nla_put_u32(obuff, PARTS, parts)) {
		pr_err("Failed to put attributes on socket buffer\n");
		return;
	}

	if (nla_put_u8(obuff, FLAGS, LUNATIK_INIT)) {
		pr_err("Failed to put attributes on socket buffer\n");
		return;
	}

	genlmsg_end(obuff, msg_head);

	if (genlmsg_reply(obuff, info) < 0) {
		pr_err("Failed to send message to user space\n");
		return;
	}

	pr_debug("Message sent to user space\n");
}

static int init_replybuffer(struct lunatik_instance *instance, size_t size)
{
	struct reply_buffer *reply_buffer = &instance->reply_buffer;
	reply_buffer->buffer = kmalloc(size * (sizeof(struct lunatik_nl_state) + DELIMITER), GFP_KERNEL);

	if (reply_buffer->buffer == NULL) {
		pr_err("Failed to allocate memory to message buffer\n");
		return -1;
	}

	fill_states_list(reply_buffer->buffer, instance);
	reply_buffer->curr_pos_to_send = 0;

	reply_buffer->parts = ((strlen(reply_buffer->buffer) % LUNATIK_FRAGMENT_SIZE) == 0) ?
						  (strlen(reply_buffer->buffer) / LUNATIK_FRAGMENT_SIZE) :
						  (strlen(reply_buffer->buffer) / LUNATIK_FRAGMENT_SIZE) + 1;
	reply_buffer->status = RB_SENDING;
	return 0;
}

static void send_lastfragment(char *fragment, struct reply_buffer *reply_buffer, struct genl_info *info)
{
	strncpy(fragment, reply_buffer->buffer + ((reply_buffer->parts - 1) * LUNATIK_FRAGMENT_SIZE), LUNATIK_FRAGMENT_SIZE);
	send_states_list(fragment, LUNATIK_DONE, info);
}

static void send_fragment(char *fragment, struct reply_buffer *reply_buffer, struct genl_info *info)
{
	strncpy(fragment, reply_buffer->buffer + (reply_buffer->curr_pos_to_send * LUNATIK_FRAGMENT_SIZE), LUNATIK_FRAGMENT_SIZE);
	send_states_list(fragment, LUNATIK_MULTI, info);
	reply_buffer->curr_pos_to_send++;
}

static int lunatikN_list(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_instance *instance;
	struct reply_buffer *reply_buffer;
	int states_count;
	char *fragment;
	int err = 0;
	u8 flags;

	pr_debug("Received a LIST_STATES command\n");

	instance = lunatik_pernet(genl_info_net(info));
	flags = *((u8 *)nla_data(info->attrs[FLAGS]));
	states_count = atomic_read(&instance->states_count);
	reply_buffer = &instance->reply_buffer;

	if ((fragment = kmalloc(LUNATIK_FRAGMENT_SIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed to allocate memory to fragment\n");
		return 0;
	}

	if (states_count == 0){
		reply_with(STATES_LIST_EMPTY, LIST_STATES, info);
		goto out;
	}

	if (reply_buffer->status == RB_INIT) {
		err = init_replybuffer(instance, states_count);
		if (err)
			reply_with(OP_ERROR, LIST_STATES, info);
		else
			send_init_information(reply_buffer->parts, states_count, info);
		goto out;
	}

	if (reply_buffer->curr_pos_to_send == reply_buffer->parts - 1) {
		send_lastfragment(fragment, reply_buffer, info);
		goto reset_reply_buffer;
	} else {
		send_fragment(fragment, reply_buffer, info);
	}

out:
	kfree(fragment);
	return 0;

reset_reply_buffer:
	reply_buffer->parts = 0;
	reply_buffer->status = RB_INIT;
	reply_buffer->curr_pos_to_send = 0;
	kfree(fragment);
	return 0;
}

static int init_data(struct lunatik_data *data, char *buffer, size_t size)
{
	if ((data->buffer = kmalloc(size, GFP_KERNEL)) == NULL) {
		pr_err("Failed to allocate memory to data buffer\n");
		return -1;
	}
	memcpy(data->buffer, buffer, size);
	data->size = size;
	return 0;
}

static int handle_data(lua_State *L);

static int lunatikN_data(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_data data;
	lunatik_State *state;
	char *payload;
	char *state_name;
	u32 payload_len;
	int err = 0;
	int base;

	state_name = nla_data(info->attrs[STATE_NAME]);

	if ((state = lunatik_netstatelookup(state_name, genl_info_net(info))) == NULL) {
		pr_err("State %s not found\n", state_name);
		goto error;
	}

	payload = nla_data(info->attrs[LUNATIK_DATA]);
	payload_len = *((u32 *)nla_data(info->attrs[LUNATIK_DATA_LEN]));

	err = init_data(&data, payload, payload_len);
	if (err)
		goto error;

	if (!lunatik_getstate(state)) {
		pr_err("Failed to get state %s\n", state_name);
		goto error;
	}

	spin_lock_bh(&state->lock);

	base = lua_gettop(state->L);
	lua_pushcfunction(state->L, handle_data);
	lua_pushlightuserdata(state->L, &data);
	if (luaU_pcall(state->L, 1, 0)) {
		pr_err("%s\n", lua_tostring(state->L, -1));
		err = -1;
		goto unlock;
	}

unlock:
	spin_unlock_bh(&state->lock);
	lua_settop(state->L, base);
	lunatik_putstate(state);

	err ? reply_with(OP_ERROR, DATA, info) : reply_with(OP_SUCESS, DATA, info);

	return 0;

error:
	reply_with(OP_ERROR, DATA, info);
	return 0;
}

static int lunatikN_datainit(struct sk_buff *buff, struct genl_info *info)
{
	lunatik_State *state;
	char *name;

	name = nla_data(info->attrs[STATE_NAME]);

	if ((state = lunatik_netstatelookup(name, genl_info_net(info))) == NULL) {
		pr_err("Failed to find the state %s\n", name);
		reply_with(OP_ERROR, DATA_INIT, info);
		return 0;
	}

	state->usr_state_info = *info;

	reply_with(OP_SUCESS, DATA_INIT, info);

	return 0;
}

int lunatikN_send_data(lunatik_State *state, const char *payload, size_t size)
{
	struct sk_buff *obuff;
	void *msg_head;

	if ((obuff = genlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating message to an reply\n");
		return 0;
	}

	if ((msg_head = genlmsg_put_reply(obuff, &state->usr_state_info, &lunatik_family, 0, DATA)) == NULL) {
		pr_err("Failed to put generic netlink header\n");
		return 0;
	}

	if (nla_put_string(obuff, LUNATIK_DATA, payload) ||
		nla_put_u32(obuff, LUNATIK_DATA_LEN, size)) {
		pr_err("Failed to put attributes on socket buffer\n");
		return 0;
	}

	genlmsg_end(obuff, msg_head);

	if (genlmsg_reply(obuff, &state->usr_state_info) < 0) {
		pr_err("Failed to send message to user space\n");
		return 0;
	}

	pr_debug("Message sent to user space\n");
	return 0;
}

static int sendstate_msg(lunatik_State *state, struct genl_info *info)
{
	struct sk_buff *obuff;
	void *msg_head;

	if ((obuff = genlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating message to an reply\n");
		return -1;
	}

	if ((msg_head = genlmsg_put_reply(obuff, info, &lunatik_family, 0, GET_STATE)) == NULL) {
		pr_err("Failed to put generic netlink header\n");
		return -1;
	}

	if (nla_put_string(obuff, STATE_NAME, state->name) ||
		nla_put_u32(obuff, MAX_ALLOC, state->maxalloc) ||
		nla_put_u32(obuff, CURR_ALLOC, state->curralloc)) {
		pr_err("Failed to put attributes on socket buffer\n");
		return -1;
	}

	genlmsg_end(obuff, msg_head);

	if (genlmsg_reply(obuff, info) < 0) {
		pr_err("Failed to send message to user space\n");
		return -1;
	}

	pr_debug("Message sent to user space\n");
	return 0;
}

static int lunatikN_sendstate(struct sk_buff *buff, struct genl_info *info)
{
	lunatik_State *state;
	char *state_name;

	state_name = nla_data(info->attrs[STATE_NAME]);

	if(((state = lunatik_netstatelookup(state_name, genl_info_net(info))) == NULL)) {
		pr_err("State %s not found\n", state_name);
		reply_with(STATE_NOT_FOUND, GET_STATE, info);
		return 0;
	}

	if (state->inuse) {
		pr_info("State %s is already in use\n", state_name);
		reply_with(OP_ERROR, GET_STATE, info);
		return 0;
	}

	if (sendstate_msg(state, info)) {
		pr_err("Failed to send message to user space\n");
		reply_with(OP_ERROR, GET_STATE, info);
	}

	state->inuse = true;

	return 0;

}

static int send_curralloc(int curralloc, struct genl_info *info)
{
	struct sk_buff *obuff;
	void *msg_head;

	if ((obuff = genlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating message to an reply\n");
		return -1;
	}

	if ((msg_head = genlmsg_put_reply(obuff, info, &lunatik_family, 0, GET_CURRALLOC)) == NULL) {
		pr_err("Failed to put generic netlink header\n");
		return -1;
	}

	if (nla_put_u32(obuff, CURR_ALLOC, curralloc)) {
		pr_err("Failed to put attributes on socket buffer\n");
		return -1;
	}

	genlmsg_end(obuff, msg_head);

	if (genlmsg_reply(obuff, info) < 0) {
		pr_err("Failed to send message to user space\n");
		return -1;
	}

	pr_debug("Message sent to user space\n");
	return 0;
}

static int lunatikN_getcurralloc(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_state *s;
	char *state_name;

	pr_debug("Received a GET_CURRALLOC message\n");

	state_name = (char *)nla_data(info->attrs[STATE_NAME]);

	s = lunatik_netstatelookup(state_name, genl_info_net(info));

	if (s == NULL)
		goto error;

	if (send_curralloc(s->curralloc, info))
		goto error;

	return 0;

error:
	reply_with(OP_ERROR, GET_CURRALLOC, info);
	return 0;
}

static int lunatikN_putstate(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_state *s;
	char *state_name;

	pr_debug("Received a PUT_STATE command\n");

	state_name = (char*)nla_data(info->attrs[STATE_NAME]);
	s = lunatik_netstatelookup(state_name, genl_info_net(info));

	if (s == NULL)
		goto error;

	if (!s->inuse) {
		reply_with(NOT_IN_USE, PUT_STATE, info);
		return 0;
	}

	if (lunatik_putstate(s))
		goto error;


	s->inuse = false;
	reply_with(OP_SUCESS, PUT_STATE, info);

	return 0;

error:
	reply_with(OP_ERROR, PUT_STATE, info);
	return 0;
}

/* Note: Most of the function below is copied from NFLua: https://github.com/cujoai/nflua
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

static int handle_data(lua_State *L)
{
	int error;
	struct lunatik_data *req = lua_touserdata(L, 1);

	lua_pop(L, 1);

	luamem_newref(L);
	luamem_setref(L, -1, req->buffer, req->size, NULL);

	if (lua_getglobal(L, DATA_RECV_FUNC) != LUA_TFUNCTION)
		return luaL_error(L, "couldn't find receive function: %s\n",
				DATA_RECV_FUNC);

	lua_pushvalue(L, 1); /* memory */

	error = lua_pcall(L, 1, 0, 0);

	luamem_setref(L, 1, NULL, 0, NULL);

	if (error)
		lua_error(L);

	return 0;
}
