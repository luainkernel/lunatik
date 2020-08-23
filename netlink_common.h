#ifndef NETLINK_COMMOM_H
#define NETLINK_COMMOM_H

#ifdef _KERNEL
extern struct genl_family lunatik_family;
#include <net/genetlink.h>
#endif /* _KERNEL */

#define LUNATIK_FRAGMENT_SIZE (3000) // TODO Find, a size more precise
#define DELIMITER 3 //How many delimiters will be necessary in each part of the message

/*Lunatik generic netlink protocol flags*/
#define LUNATIK_INIT	0x01 /* Initializes the needed variables for script execution */
#define LUNATIK_MULTI	0x02 /* A Fragment of a multipart message					  */
#define LUNATIK_DONE	0x04 /* Last message of a multipart message 				  */

#define LUNATIK_FAMILY "lunatik_family"
#define LUNATIK_NLVERSION 1

enum lunatik_operations {
	CREATE_STATE = 1, /* Starts at 1 because 0 is used by generic netlink */
	EXECUTE_CODE,
	DESTROY_STATE,
	LIST_STATES,
	DATA,
	DATA_INIT,
	GET_STATE,
	GET_CURRALLOC,
};

enum lunatik_attrs {
	STATE_NAME = 1,
	MAX_ALLOC,
	STATES_LIST,
	STATES_COUNT,
	PARTS,
	CODE,
	FLAGS,
	SCRIPT_SIZE,
	SCRIPT_NAME,
	STATES_LIST_EMPTY,
	OP_SUCESS,
	OP_ERROR,
	LUNATIK_DATA,
	LUNATIK_DATA_LEN,
	CURR_ALLOC,
	STATE_NOT_FOUND,
	ATTRS_COUNT
#define ATTRS_MAX (ATTRS_COUNT - 1)
};

#endif /* NETLINK_COMMOM_H */
