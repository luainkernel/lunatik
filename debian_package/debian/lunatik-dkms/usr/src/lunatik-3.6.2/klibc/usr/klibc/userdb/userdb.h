/*
 * userdb.h
 *
 * Common header file
 */

#ifndef USERDB_H
#define USERDB_H

#include <sys/types.h>
#include <pwd.h>
#include <grp.h>
#include <string.h>
#include <errno.h>

extern const struct passwd __root_user;
extern const struct group __root_group;

#endif /* USERDB_H */
