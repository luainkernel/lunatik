#ifndef _SYS_CAPABILITY_H
#define _SYS_CAPABILITY_H

#include <sys/types.h>
#include <klibc/extern.h>
#include <linux/capability.h>

__extern int capget(cap_user_header_t, cap_user_data_t);
__extern int capset(cap_user_header_t, const cap_user_data_t);

#endif				/* _SYS_CAPABILITY_H */
