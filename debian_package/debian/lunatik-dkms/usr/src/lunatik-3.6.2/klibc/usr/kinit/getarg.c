#include <string.h>
#include "kinit.h"

/*
 * Routines that hunt for a specific argument.  Please note that
 * they actually search the array backwards.  That is because on the
 * kernel command lines, it's legal to override an earlier argument
 * with a later argument.
 */

/*
 * Was this boolean argument passed?  If so return the index in the
 * argv array for it.  For conflicting boolean options, use the
 * one with the higher index.  The only case when the return value
 * can be equal, is when they're both zero; so equality can be used
 * as the default option choice.
 *
 * In other words, if two options "a" and "b" are opposites, and "a"
 * is the default, this can be coded as:
 *
 * if (get_flag(argc,argv,"a") >= get_flag(argc,argv,"b"))
 * 	do_a_stuff();
 * else
 *	do_b_stuff();
 */
int get_flag(int argc, char *argv[], const char *name)
{
	int i;

	for (i = argc-1; i > 0; i--) {
		if (!strcmp(argv[i], name))
			return i;
	}
	return 0;
}

/*
 * Was this textual parameter (foo=option) passed?
 *
 * This returns the latest instance of such an option in the argv array.
 */
char *get_arg(int argc, char *argv[], const char *name)
{
	int len = strlen(name);
	char *ret = NULL;
	int i;

	for (i = argc-1; i > 0; i--) {
		if (argv[i] && strncmp(argv[i], name, len) == 0 &&
		    (argv[i][len] != '\0')) {
			ret = argv[i] + len;
			break;
		}
	}

	return ret;
}
