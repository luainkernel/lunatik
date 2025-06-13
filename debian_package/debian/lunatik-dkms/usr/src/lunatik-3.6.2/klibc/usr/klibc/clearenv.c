/*
 * clearenv.c
 *
 * Empty the environment
 */

#include <stdlib.h>
#include <unistd.h>
#include "env.h"

/* Note: if environ has been malloc'd, it will be freed on the next
   setenv() or putenv() */
int clearenv(void)
{
	environ = (char **)__null_environ;
	return 0;
}
