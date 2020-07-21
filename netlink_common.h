#ifndef NETLINK_COMMOM_H
#define NETLINK_COMMOM_H

#ifdef _KERNEL
extern struct genl_family lunatik_family;
#include <net/genetlink.h>

struct reply_buffer {
	lunatik_State *states_list;
	int list_size;
	int curr_pos_to_send;
};
#endif

#define LUNATIK_FRAGMENT_SIZE (3000) // TODO Find, a size more precise

/*Lunatik generic netlink protocol flags*/
#define LUNATIK_INIT	0x01 /* Initializes the needed variables for script execution */
#define LUNATIK_MULTI	0x02 /* A Fragment of a multipart message  					  */
#define LUNATIK_DONE	0x04 /* Last message of a multipart message 				  */ 

#define LUNATIK_FAMILY "lunatik_family"
#define LUNATIK_NLVERSION 1

enum lunatik_operations {
	CREATE_STATE = 1, /* Starts at 1 because 0 is used by generic netlink */
	EXECUTE_CODE,
	DESTROY_STATE,
	LIST_STATES,
};

enum lunatik_attrs {
	STATE_NAME = 1,
	STATES_COUNT,
	MAX_ALLOC,
	CURR_ALLOC,
	CODE,
	FLAGS,
	SCRIPT_SIZE,
	SCRIPT_NAME,
	OP_SUCESS,
	OP_ERROR,
	ATTRS_COUNT
#define ATTRS_MAX (ATTRS_COUNT - 1)
};

#endif /* NETLINK_COMMOM_H */
