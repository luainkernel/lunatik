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

#ifndef NETLINK_H
#define NETLINK_H
#include <net/genetlink.h>

#include "lunatik.h"

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

#endif /* NETLINK_H */
