#ifndef NETLINK_H
#include <net/genetlink.h>

extern struct genl_family lunatik_family;

enum reply_buffer_status {
	RB_INIT,
	RB_SENDING,
};

struct reply_buffer {
	char *buffer;
	int parts;
	int curr_pos_to_send;
	enum reply_buffer_status status;
};

struct lunatik_data {
    char *buffer;
    size_t size;
};

#endif

