/*
 * scandir.c: scandir
 */

#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include <dirent.h>

int scandir(const char *dirp, struct dirent ***namelist,
	    int (*filter)(const struct dirent *),
	    int (*compar)(const struct dirent **, const struct dirent **))
{
	struct dirent **nl = NULL, **next_nl;
	struct dirent *dirent;
	size_t count = 0;
	size_t allocated = 0;
	DIR *dir;

	dir = opendir(dirp);
	if (!dir)
		return -1;

	while (1) {
		dirent = readdir(dir);
		if (!dirent)
			break;
		if (!filter || filter(dirent)) {
			struct dirent *copy;
			copy = malloc(sizeof(*copy));
			if (!copy)
				goto cleanup_fail;
			memcpy(copy, dirent, sizeof(*copy));

			/* Extend the array if needed */
			if (count == allocated) {
				if (allocated == 0)
					allocated = 15; /* ~1 page worth */
				else
					allocated *= 2;
				next_nl = realloc(nl, allocated);
				if (!next_nl) {
					free(copy);
					goto cleanup_fail;
				}
				nl = next_nl;
			}

			nl[count++] = copy;
		}
	}

	qsort(nl, count, sizeof(struct dirent *),
	      (int (*)(const void *, const void *))compar);

	closedir(dir);

	*namelist = nl;
	return count;

cleanup_fail:
	while (count) {
		dirent = nl[--count];
		free(dirent);
	}
	free(nl);
	closedir(dir);
	errno = ENOMEM;
	return -1;
}
