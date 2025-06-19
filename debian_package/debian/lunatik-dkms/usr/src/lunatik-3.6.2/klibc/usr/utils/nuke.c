/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2004-2006 H. Peter Anvin - All Rights Reserved
 *
 *   Permission is hereby granted, free of charge, to any person
 *   obtaining a copy of this software and associated documentation
 *   files (the "Software"), to deal in the Software without
 *   restriction, including without limitation the rights to use,
 *   copy, modify, merge, publish, distribute, sublicense, and/or
 *   sell copies of the Software, and to permit persons to whom
 *   the Software is furnished to do so, subject to the following
 *   conditions:
 *
 *   The above copyright notice and this permission notice shall
 *   be included in all copies or substantial portions of the Software.
 *
 *   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 *   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 *   OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 *   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 *   HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 *   WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 *   OTHER DEALINGS IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------- */

/*
 * Simple program which does the same thing as rm -rf, except it takes
 * no options and can therefore not get confused by filenames starting
 * with -.  Similarly, an empty list of inputs is assumed to mean don't
 * do anything.
 */

#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

static const char *program;

static int nuke(const char *what);

static int nuke_dirent(int len, const char *dir, const char *name)
{
	int bytes = len + strlen(name) + 2;
	char path[bytes];
	int xlen;

	xlen = snprintf(path, bytes, "%s/%s", dir, name);
	assert(xlen < bytes);

	return nuke(path);
}

/* Wipe the contents of a directory, but not the directory itself */
static int nuke_dir(const char *what)
{
	int len = strlen(what);
	DIR *dir;
	struct dirent *d;
	int err = 0;

	dir = opendir(what);
	if (!dir) {
		/* EACCES means we can't read it.  Might be empty and removable;
		   if not, the rmdir() in nuke() will trigger an error. */
		return (errno == EACCES) ? 0 : errno;
	}

	while ((d = readdir(dir))) {
		/* Skip . and .. */
		if (d->d_name[0] == '.' &&
		    (d->d_name[1] == '\0' ||
		     (d->d_name[1] == '.' && d->d_name[2] == '\0')))
			continue;

		err = nuke_dirent(len, what, d->d_name);
		if (err) {
			closedir(dir);
			return err;
		}
	}

	closedir(dir);

	return 0;
}

static int nuke(const char *what)
{
	int rv;
	int err = 0;

	rv = unlink(what);
	if (rv < 0) {
		if (errno == EISDIR) {
			/* It's a directory. */
			err = nuke_dir(what);
			if (!err)
				rmdir(what);
		}
	}

	return 0;
}

int main(int argc, char *argv[])
{
	int i;

	program = argv[0];

	for (i = 1; i < argc; i++)
		nuke(argv[i]);

	return 0;
}
