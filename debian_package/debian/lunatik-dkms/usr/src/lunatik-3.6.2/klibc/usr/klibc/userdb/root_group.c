/*
 * root_group.c
 */

#include "userdb.h"

const struct group __root_group = {
	.gr_name   = "root",
	.gr_passwd = "",
	.gr_gid    = 0,
	.gr_mem    = NULL
};
