/*
 * root_user.c
 *
 */

#include "userdb.h"
#include <paths.h>

const struct passwd __root_user = {
	.pw_name    = "root",
	.pw_passwd  = "",
	.pw_uid     = 0,
	.pw_gid     = 0,
	.pw_gecos   = "root",
	.pw_dir     = "/",
	.pw_shell   = _PATH_BSHELL
};
