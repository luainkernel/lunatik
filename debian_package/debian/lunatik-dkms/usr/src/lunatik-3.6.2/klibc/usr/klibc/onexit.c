/*
 * onexit.c
 */

#include <stdlib.h>
#include <unistd.h>
#include "atexit.h"

int on_exit(void (*fctn) (int, void *), void *arg)
{
	struct atexit *as = malloc(sizeof(struct atexit));

	if (!as)
		return -1;

	as->fctn = fctn;
	as->arg = arg;

	as->next = __atexit_list;
	__atexit_list = as;

	return 0;
}
