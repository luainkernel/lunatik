#include <sys/sysconf.h>

#undef sysconf

long sysconf(int val)
{
	return __sysconf_inline(val);
}
