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

extern struct lunatik_session *lunatik_pernet(struct net *net);

static int lunatikN_newstate(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_exec(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_close(struct sk_buff *buff, struct genl_info *info);
static int lunatikN_list(struct sk_buff *buff, struct genl_info *info);

struct nla_policy lunatik_policy[ATTRS_COUNT] = {
	[STATE_NAME]  = { .type = NLA_STRING },
	[CODE]		  = { .type = NLA_STRING },
	[MAX_ALLOC]   = { .type = NLA_U32 },
	[SCRIPT_SIZE] = { .type = NLA_U32 }, //TODO See what is the maximum script size accepted by the module
	[STATES_COUNT]= { .type = NLA_U32},	
	[FLAGS] 	  = { .type = NLA_U8 },
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
		.doit   = lunatikN_exec,
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
	.netnsok = true, /*Make this family visible for all namespaces*/
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,2,0)
	.policy  = lunatik_policy,
#endif
	.module  = THIS_MODULE,
	.ops     = l_ops,
	.n_ops   = ARRAY_SIZE(l_ops),
};

static int lunatikN_newstate(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_session *session;
	char *state_name;
	u32 *max_alloc;
	u32 pid;

	pr_debug("Received a CREATE_STATE message\n");
	
	session = lunatik_pernet(genl_info_net(info));
	state_name = (char *)nla_data(info->attrs[STATE_NAME]);
	max_alloc = (u32 *)nla_data(info->attrs[MAX_ALLOC]);
	pid = info->snd_portid;

	lunatik_newstate(session, *max_alloc, state_name);

	return 0;
}

static int lunatikN_exec(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_state *s;
	struct lunatik_session *session;
	const char *finalscript;
	char *fragment;
	char *state_name;
	u8 flags;

	pr_debug("Received a EXECUTE_CODE message\n");

	session = lunatik_pernet(genl_info_net(info));
	state_name = (char *)nla_data(info->attrs[STATE_NAME]);
	fragment = (char *)nla_data(info->attrs[CODE]);
	flags = *((u8*)nla_data(info->attrs[FLAGS]));

	if ((s = lunatik_netstatelookup(session, state_name)) == NULL) {
		pr_err("Error finding klua state\n");
		return 0;
	}

	if (flags & LUNATIK_INIT) {
		s->curr_script_size = *((u32*)nla_data(info->attrs[SCRIPT_SIZE]));
		
		if ((s->buffer = kmalloc(sizeof(luaL_Buffer), GFP_KERNEL)) == NULL) {
			pr_err("Failed allocating memory to code buffer\n");
			return 0;
		}
		spin_lock_bh(&s->lock);
		luaL_buffinit(s->L, s->buffer);	
	} // TODO Otherwise, reply with a "busy state"

	if (flags & LUNATIK_MULTI) {
		luaL_addlstring(s->buffer, fragment, LUNATIK_FRAGMENT_SIZE);
	}

	if (flags & LUNATIK_DONE){
		luaL_addstring(s->buffer, fragment);
		luaL_pushresult(s->buffer);

		finalscript = lua_tostring(s->L, -1);
		
		if (!lunatik_state_get(s)) {
			pr_err("Failed to get state\n");
			return 0;
		}

		if (luaU_dostring(s->L, finalscript, s->curr_script_size, "Lua in kernel")) {
			pr_err("%s\n", lua_tostring(s->L, -1));
		}
		
		spin_unlock_bh(&s->lock);
		lunatik_state_put(s);
	}

	return 0;
}

static int lunatikN_close(struct sk_buff *buff, struct genl_info *info)
{
	struct lunatik_session *session;
	char *state_name;
	
	session = lunatik_pernet(genl_info_net(info));
	state_name = (char *)nla_data(info->attrs[STATE_NAME]);
	
	pr_debug("Received a DESTROY_STATE command\n");

	if (lunatik_close(session, state_name)) {
		pr_err("Failed to destroy state %s\n", state_name);
		return 0;
	}	

	return 0;
}

static int lunatikN_list(struct sk_buff *buff, struct genl_info *info)
{
	struct sk_buff *obuff;
	struct lunatik_session *session;
	struct lunatik_state *state;
	void *msg_head;
	int bucket;
	bool firstmsg = true;
	int err = -1;

	pr_debug("Received a LIST_STATES command\n");

	session = lunatik_pernet(genl_info_net(info));

	hash_for_each_rcu(session->states_table, bucket, state, node) {
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

		if (firstmsg) {
			if (nla_put_u32(obuff, STATES_COUNT, atomic_read(&session->states_count)) ||
				nla_put_u8(obuff, FLAGS, LUNATIK_INIT)
			   ) {
				pr_err("Failed to put attributes on socket buffer\n");
				return err;
			}
			firstmsg = false;
  		
		} else if (nla_put_u8(obuff, FLAGS, 0)) {
			pr_err("Failed to put attributes on socket buffer\n");
			return err;
		}

		genlmsg_end(obuff, msg_head);

		if (genlmsg_reply(obuff, info) < 0) {
			pr_err("Failed to send message to user space\n");
			return err;
		}

		pr_debuf("Message sento to kernel\n");
	}

	return 0;
}
