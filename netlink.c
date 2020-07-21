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

#include "luautil.h"
#include "states.h"
#include "netlink_common.h"

extern struct lunatik_instance *lunatik_pernet(struct net *net);

static int lunatikN_newstate(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_dostring(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_close(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_list(struct sk_buff *buff, struct genl_info *info);

struct nla_policy lunatik_policy[ATTRS_COUNT] = {
	[STATE_NAME]  = { .type = NLA_STRING },
	[CODE]		  = { .type = NLA_STRING },
	[SCRIPT_NAME] = { .type = NLA_STRING},
	[MAX_ALLOC]   = { .type = NLA_U32 },
	[SCRIPT_SIZE] = { .type = NLA_U32 },
	[STATES_COUNT]= { .type = NLA_U32},	
	[FLAGS] 	  = { .type = NLA_U8 },
	[OP_SUCESS]   = { .type = NLA_U8 },
	[OP_ERROR]	  = { .type = NLA_U8},
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
		/*Before kernel 5.2.0, each operation has its own policy*/
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = DESTROY_STATE,
		.doit   = lunatikN_close,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		/*Before kernel 5.2.0, each operation has its own policy*/
		.policy = lunatik_policy
#endif
	},
	{
		.cmd    = LIST_STATES,
		.doit   = lunatikN_list,
#if LINUX_VERSION_CODE < KERNEL_VERSION(5,2,0)
		/*Before kernel 5.2.0, each operation has its own policy*/
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

static int fill_reply_buffer(struct reply_buffer *message, struct lunatik_instance *instance)
{
	struct lunatik_state *state;
	int bucket;
	int states_count = atomic_read(&(instance->states_count));
	int counter = 0;

	message->states_list = kmalloc(states_count * sizeof(lunatik_State), GFP_KERNEL);

	if (message->states_list == NULL) {
		pr_err("Failed to allocate memory to hold states list\n");
		return -ENOMEM;
	}

	message->list_size = states_count;
	message->curr_pos_to_send = 0;
	hash_for_each_rcu(instance->states_table, bucket, state, node) {
		message->states_list[counter] = *(state);
		counter++;
	}

	return 0;
}

static int send_done_msg(int command, struct genl_info *info)
{
	void *msg_head;
	struct sk_buff *obuff;
	int err = -1;

	if ((obuff = genlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating message to an reply\n");
		return -ENOMEM;
	}

	if ((msg_head = genlmsg_put_reply(obuff, info, &lunatik_family, 0, command)) == NULL) {
		pr_err("Failed to put generic netlink header\n");
		return err;
	}

	nla_put_u8(obuff, FLAGS, LUNATIK_DONE);

	genlmsg_end(obuff, msg_head);

	if (genlmsg_reply(obuff, info) < 0) {
		pr_err("Failed to send message to user space\n");
		return err;
	}

	return 0;
}

static int send_states_count(struct lunatik_instance *instance, struct genl_info *info)
{
	void *msg_head;
	struct sk_buff *obuff;
	int err = -1;

	if ((obuff = genlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating message to an reply\n");
		return -ENOMEM;
	}

	if ((msg_head = genlmsg_put_reply(obuff, info, &lunatik_family, 0, LIST_STATES)) == NULL) {
		pr_err("Failed to put generic netlink header\n");
		return err;
	}

	nla_put_u8(obuff, FLAGS, LUNATIK_INIT);
	nla_put_u32(obuff, STATES_COUNT, atomic_read(&instance->states_count));

	genlmsg_end(obuff, msg_head);

	if (genlmsg_reply(obuff, info) < 0) {
		pr_err("Failed to send message to user space\n");
		return err;
	}

	return 0;
}

static int send_state(lunatik_State *state, struct genl_info *info)
{
	struct sk_buff *obuff;
	void *msg_head;
	int err = -1;

	if ((obuff = genlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL)) == NULL) {
		pr_err("Failed allocating message to an reply\n");
		return err;
	}

	if ((msg_head = genlmsg_put_reply(obuff, info, &lunatik_family, 0, LIST_STATES)) == NULL) {
		pr_err("Failed to put generic netlink header\n");
		return err;
	}

	if (nla_put_string(obuff, STATE_NAME, state->name)   ||
		nla_put_u32(obuff, MAX_ALLOC, state->maxalloc)	 ||
		nla_put_u32(obuff, CURR_ALLOC, state->curralloc) 
		) {
		pr_err("Failed to put attributes on socket buffer\n");
		return err;
	}

	genlmsg_end(obuff, msg_head);

	if (genlmsg_reply(obuff, info) < 0) {
		pr_err("Failed to send message to user space\n");
		return err;
	}

	pr_debug("Message sent to user space\n");

	return 0;
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

static int lunatikN_newstate(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_instance *instance;
	struct lunatik_state *s;
	char *state_name;
	u32 *max_alloc;
	u32 pid;

	pr_debug("Received a CREATE_STATE message\n");

	instance = lunatik_pernet(genl_info_net(info));
	state_name = (char *)nla_data(info->attrs[STATE_NAME]);
	max_alloc = (u32 *)nla_data(info->attrs[MAX_ALLOC]);
	pid = info->snd_portid;

	s = lunatik_netnewstate(instance, *max_alloc, state_name);

	s == NULL ? reply_with(OP_ERROR, CREATE_STATE, info) : reply_with(OP_SUCESS, CREATE_STATE, info);

	return 0;
}

static int lunatikN_dostring(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_state *s;
	struct lunatik_instance *instance;
	const char *finalscript;
	const char *script_name;
	int err;
	char *fragment;
	char *state_name;
	u8 flags;

	pr_debug("Received a EXECUTE_CODE message\n");

	instance = lunatik_pernet(genl_info_net(info));
	state_name = (char *)nla_data(info->attrs[STATE_NAME]);
	fragment = (char *)nla_data(info->attrs[CODE]);
	flags = *((u8*)nla_data(info->attrs[FLAGS]));

	if ((s = lunatik_netstatelookup(instance, state_name)) == NULL) {
		pr_err("Error finding klua state\n");
		reply_with(OP_ERROR, EXECUTE_CODE, info);
		return 0;
	}

	if (flags & LUNATIK_INIT) {
		s->scriptsize = *((u32*)nla_data(info->attrs[SCRIPT_SIZE]));

		/*TODO Discover why this lock when disable bh is causing a kernel panic related to skb release
		*/
		spin_lock(&s->lock);
		if ((s->buffer = kmalloc(sizeof(luaL_Buffer), GFP_KERNEL)) == NULL) {
			pr_err("Failed allocating memory to code buffer\n");
			reply_with(OP_ERROR, EXECUTE_CODE, info);
			return 0;
		}
		luaL_buffinit(s->L, s->buffer);		
	}

	if (flags & LUNATIK_MULTI) {
		luaL_addlstring(s->buffer, fragment, LUNATIK_FRAGMENT_SIZE);
	}

	if (flags & LUNATIK_DONE){
		luaL_addstring(s->buffer, fragment);
		luaL_pushresult(s->buffer);

		finalscript = lua_tostring(s->L, -1);
		script_name = nla_data(info->attrs[SCRIPT_NAME]);
		
		if (!lunatik_stateget(s)) {
			pr_err("Failed to get state\n");
			reply_with(OP_ERROR, EXECUTE_CODE, info);
			return 0;
		}

		if ((err = luaU_dostring(s->L, finalscript, s->scriptsize, script_name))) {
			pr_err("%s\n", lua_tostring(s->L, -1));
		}
		
		spin_unlock(&s->lock);
		lunatik_stateput(s);
		
		err ? reply_with(OP_ERROR, EXECUTE_CODE, info) : reply_with(OP_SUCESS, EXECUTE_CODE, info);
	}

	return 0;
}

static int lunatikN_close(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_instance *instance;
	char *state_name;

	instance = lunatik_pernet(genl_info_net(info));
	state_name = (char *)nla_data(info->attrs[STATE_NAME]);

	pr_debug("Received a DESTROY_STATE command\n");

	if (lunatik_netclose(instance, state_name))
		reply_with(OP_ERROR, DESTROY_STATE, info);
	else
		reply_with(OP_SUCESS, DESTROY_STATE, info);

	return 0;
}

static int lunatikN_list(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_instance *instance;
	struct reply_buffer *reply;
	lunatik_State currstate;
	u8 flags;

	pr_debug("Received a LIST_STATES command\n");

	instance = lunatik_pernet(genl_info_net(info));
	flags = *((u8 *)nla_data(info->attrs[FLAGS]));
	reply = instance->reply_buffer;

	if (flags & LUNATIK_INIT) {
		spin_lock(&(instance->sendmessage_lock));
		fill_reply_buffer(reply, instance); // TODO Check error and reply if an error occur
		send_states_count(instance, info);
		goto out;
	}

	if (reply->curr_pos_to_send == reply->list_size) {
		send_done_msg(LIST_STATES, info);
		kfree(reply->states_list);
		spin_unlock(&(instance->sendmessage_lock));
		goto out;
	}

	currstate = reply->states_list[reply->curr_pos_to_send++];
	if (send_state(&currstate, info)) {
		pr_err("Failed to send state information to user space\n");
		return 0;
	}

out:
	return 0;
}
