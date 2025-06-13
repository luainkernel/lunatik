#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/sysmacros.h>

#define STAT_ISSET(mode, mask) (((mode) & mask) == mask)

static size_t max_linksiz = 128;
static int max_nlinks = 1;
static int max_size = 1;
static int max_uid = 1;
static int max_gid = 1;
static int max_min = 1;
static int max_maj = 1;

static void do_preformat(const struct stat *st)
{
	int bytes;

	bytes = snprintf(NULL, 0, "%ju", (uintmax_t) st->st_nlink);
	if (bytes > max_nlinks)
		max_nlinks = bytes;

	bytes = snprintf(NULL, 0, "%ju", (uintmax_t) st->st_uid);
	if (bytes > max_uid)
		max_uid = bytes;

	bytes = snprintf(NULL, 0, "%ju", (uintmax_t) st->st_gid);
	if (bytes > max_gid)
		max_gid = bytes;

	if (S_ISCHR(st->st_mode) || S_ISBLK(st->st_mode)) {
		bytes = snprintf(NULL, 0, "%u", major(st->st_rdev));
		if (bytes > max_maj)
			max_maj = bytes;

		bytes = snprintf(NULL, 0, "%u", minor(st->st_rdev));
		if (bytes > max_min)
			max_min = bytes;

		max_size = max_maj + max_min + 1;
	} else {
		bytes = snprintf(NULL, 0, "%ju", (uintmax_t) st->st_size);
		if (bytes > max_size)
			max_size = bytes;
	}
	return;
}

static void do_stat(const struct stat *st, int dir_fd, const char *path)
{
	char *fmt, *link_name;
	int rc;

	switch (st->st_mode & S_IFMT) {
	case S_IFBLK:
		putchar('b');
		break;
	case S_IFCHR:
		putchar('c');
		break;
	case S_IFDIR:
		putchar('d');
		break;
	case S_IFIFO:
		putchar('p');
		break;
	case S_IFLNK:
		putchar('l');
		break;
	case S_IFSOCK:
		putchar('s');
		break;
	case S_IFREG:
		putchar('-');
		break;
	default:
		putchar('?');
		break;
	}
	putchar(STAT_ISSET(st->st_mode, S_IRUSR) ? 'r' : '-');
	putchar(STAT_ISSET(st->st_mode, S_IWUSR) ? 'w' : '-');

	!STAT_ISSET(st->st_mode, S_ISUID) ?
		putchar(STAT_ISSET(st->st_mode, S_IXUSR) ? 'x' : '-') :
		putchar('S');

	putchar(STAT_ISSET(st->st_mode, S_IRGRP) ? 'r' : '-');
	putchar(STAT_ISSET(st->st_mode, S_IWGRP) ? 'w' : '-');

	!STAT_ISSET(st->st_mode, S_ISGID) ?
		putchar(STAT_ISSET(st->st_mode, S_IXGRP) ? 'x' : '-') :
		putchar('S');

	putchar(STAT_ISSET(st->st_mode, S_IROTH) ? 'r' : '-');
	putchar(STAT_ISSET(st->st_mode, S_IWOTH) ? 'w' : '-');

	!STAT_ISSET(st->st_mode, S_ISVTX) ?
		putchar(STAT_ISSET(st->st_mode, S_IXOTH) ? 'x' : '-') :
		putchar(S_ISDIR(st->st_mode) ? 't' : 'T');

	if (S_ISCHR(st->st_mode) || S_ISBLK(st->st_mode)) {
		rc = asprintf(&fmt, " %%%dju %%%dju %%%dju %%%du,%%%du %%s",
				max_nlinks, max_uid, max_gid, max_maj, max_min);
		if (rc == -1) {
			perror("asprintf");
			exit(1);
		}
		fprintf(stdout, fmt,
			(uintmax_t) st->st_nlink,
			(uintmax_t) st->st_uid,
			(uintmax_t) st->st_gid,
			major(st->st_rdev),
			minor(st->st_rdev),
			path);
	} else {
		rc = asprintf(&fmt, " %%%dju %%%dju %%%dju %%%dju %%s",
				max_nlinks, max_uid, max_gid, max_size);
		if (rc == -1) {
			perror("asprintf");
			exit(1);
		}
		fprintf(stdout, fmt,
			(uintmax_t) st->st_nlink,
			(uintmax_t) st->st_uid,
			(uintmax_t) st->st_gid,
			(uintmax_t) st->st_size,
			path);
	}
	free(fmt);

	if (S_ISLNK(st->st_mode)) {
		link_name = malloc(max_linksiz);
		if (link_name == NULL) {
			perror("malloc");
			exit(1);
		}
		rc = readlinkat(dir_fd, path, link_name, max_linksiz);
		if (rc == -1) {
			free(link_name);
			perror("readlink");
			exit(1);
		}
		link_name[rc] = '\0';
		fprintf(stdout, " -> %s", link_name);
		free(link_name);
	}

	putchar('\n');
	return;
}

static void do_dir(const char *path, int preformat)
{
	DIR *dir;
	int dir_fd;
	struct dirent *dent;
	struct stat st;

	dir = opendir(path);
	if (dir == NULL) {
		perror(path);
		exit(1);
	}
	dir_fd = dirfd(dir);

	while ((dent = readdir(dir)) != NULL) {
		if (fstatat(dir_fd, dent->d_name, &st,
			    AT_SYMLINK_NOFOLLOW)) {
			perror(dent->d_name);
			exit(1);
		}
		(preformat) ?
			do_preformat(&st) :
			do_stat(&st, dir_fd, dent->d_name);
	}

	closedir(dir);
}

int main(int argc, char *argv[])
{
	int i;
	struct stat st;

	if (argc == 1) {
		do_dir(".", 1);
		do_dir(".", 0);
		return 0;
	}

	for (i = 1; i < argc; i++) {
		if (argv[i][0] == '-' && argv[i][1] == 'h') {
			fprintf(stdout, "Usage: ls [-h] [FILE ...]\n");
			return 0;
		}

		if (lstat(argv[i], &st)) {
			perror(argv[i]);
			exit(1);
		}

		S_ISDIR(st.st_mode) ?
			do_dir(argv[i], 1) :
			do_preformat(&st);
	}

	for (i = 1; i < argc; i++) {
		if (lstat(argv[i], &st)) {
			perror(argv[i]);
			exit(1);
		}

		S_ISDIR(st.st_mode) ?
			do_dir(argv[i], 0) :
			do_stat(&st, AT_FDCWD, argv[i]);
	}

	return 0;
}
