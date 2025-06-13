#include <sys/mount.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <alloca.h>
#include <limits.h>
#include <ctype.h>
#include <termios.h>

#include "kinit.h"
#include "ipconfig.h"
#include "run-init.h"
#include "resume.h"

const char *progname = "kinit";
int mnt_procfs;
int mnt_sysfs;

#ifdef DEBUG
void dump_args(int argc, char *argv[])
{
	int i;

	printf("  argc == %d\n", argc);

	for (i = 0; i < argc; i++)
		printf("  argv[%d]: \"%s\"\n", i, argv[i]);

	if (argv[argc] != NULL)
		printf("  argv[%d]: \"%s\" (SHOULD BE NULL)\n",
			argc, argv[argc]);
}
#endif /* DEBUG */


static int do_ipconfig(int argc, char *argv[])
{
	int i, a = 0;
	char **args = alloca((argc + 3) * sizeof(char *));

	if (!args)
		return -1;

	args[a++] = (char *)"IP-Config";
	args[a++] = (char *)"-i";
	args[a++] = (char *)"Linux kinit";

	dprintf("Running ipconfig\n");

	for (i = 1; i < argc; i++) {
		if (strncmp(argv[i], "ip=", 3) == 0 ||
		    strncmp(argv[i], "nfsaddrs=", 9) == 0) {
			args[a++] = argv[i];
		}
	}

	if (a > 1) {
		args[a] = NULL;
		dump_args(a, args);
		return ipconfig_main(a, args);
	}

	return 0;
}

static int split_cmdline(int cmdcmax, char *cmdv[], char *argv0,
			 char *cmdlines[], char *args[])
{
	int was_space;
	char c, *p;
	int vmax = cmdcmax;
	int v = 1;
	int space;

	if (cmdv)
		cmdv[0] = argv0;

	/* First, add the parsable command lines */

	while (*cmdlines) {
		p = *cmdlines++;
		was_space = 1;
		while (v < vmax) {
			c = *p;
			space = isspace(c);
			if ((space || !c) && !was_space) {
				if (cmdv)
					*p = '\0';
				v++;
			} else if (was_space) {
				if (cmdv)
					cmdv[v] = p;
			}

			if (!c)
				break;

			was_space = space;
			p++;
		}
	}

	/* Second, add the explicit command line arguments */

	while (*args && v < vmax) {
		if (cmdv)
			cmdv[v] = *args;
		v++;
		args++;
	}

	if (cmdv)
		cmdv[v] = NULL;

	return v;
}

static int mount_sys_fs(const char *check, const char *fsname,
			const char *fstype)
{
	struct stat st;

	if (stat(check, &st) == 0)
		return 0;

	mkdir(fsname, 0555);

	if (mount("none", fsname, fstype, 0, NULL) == -1) {
		fprintf(stderr, "%s: could not mount %s as %s\n",
			progname, fsname, fstype);
		return -1;
	}

	return 1;
}

static void check_path(const char *path)
{
	struct stat st;

	if (stat(path, &st) == -1) {
		if (errno != ENOENT) {
			perror("stat");
			exit(1);
		}
		if (mkdir(path, 0755) == -1) {
			perror("mkdir");
			exit(1);
		}
	} else if (!S_ISDIR(st.st_mode)) {
		fprintf(stderr, "%s: '%s' not a directory\n", progname, path);
		exit(1);
	}
}

static const char *find_init(const char *root, const char *user)
{
	const char *init_paths[] = {
		"/sbin/init", "/bin/init", "/etc/init", "/bin/sh", NULL
	};
	const char **p;
	const char *path;

	if (chdir(root)) {
		perror("chdir");
		exit(1);
	}

	if (user)
		dprintf("Checking for init: %s\n", user);

	if (user && user[0] == '/' && !access(user+1, X_OK)) {
		path = user;
	} else {
		for (p = init_paths; *p; p++) {
			dprintf("Checking for init: %s\n", *p);
			if (!access(*p+1, X_OK))
				break;
		}
		path = *p;
	}
	chdir("/");
	return path;
}

/* This is the argc and argv we pass to init */
const char *init_path;
int init_argc;
char **init_argv;

extern ssize_t readfile(const char *, char **);

int main(int argc, char *argv[])
{
	char **cmdv, **args;
	char *cmdlines[3];
	int i;
	const char *errmsg;
	int ret = 0;
	int cmdc;
	int fd;
	struct timeval now;

	gettimeofday(&now, NULL);
	srand48(now.tv_usec ^ (now.tv_sec << 24));

	/* Default parameters for anything init-like we execute */
	init_argc = argc;
	init_argv = alloca((argc+1)*sizeof(char *));
	memcpy(init_argv, argv, (argc+1)*sizeof(char *));

	if ((fd = open("/dev/console", O_RDWR)) != -1) {
		dup2(fd, STDIN_FILENO);
		dup2(fd, STDOUT_FILENO);
		dup2(fd, STDERR_FILENO);

		if (fd > STDERR_FILENO)
			close(fd);
	}

	mnt_procfs = mount_sys_fs("/proc/cmdline", "/proc", "proc") >= 0;
	if (!mnt_procfs) {
		ret = 1;
		goto bail;
	}

	mnt_sysfs = mount_sys_fs("/sys/bus", "/sys", "sysfs") >= 0;
	if (!mnt_sysfs) {
		ret = 1;
		goto bail;
	}

	/* Construct the effective kernel command line.  The
	   effective kernel command line consists of /arch.cmd, if
	   it exists, /proc/cmdline, plus any arguments after an --
	   argument on the proper command line, in that order. */

	ret = readfile("/arch.cmd", &cmdlines[0]);
	if (ret < 0)
		cmdlines[0] = "";

	ret = readfile("/proc/cmdline", &cmdlines[1]);
	if (ret < 0) {
		fprintf(stderr, "%s: cannot read /proc/cmdline\n", progname);
		ret = 1;
		goto bail;
	}

	cmdlines[2] = NULL;

	/* Find an -- argument, and if so append to the command line */
	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--")) {
			i++;
			break;
		}
	}
	args = &argv[i];	/* Points either to first argument past -- or
				   to the final NULL */

	/* Count the number of arguments */
	cmdc = split_cmdline(INT_MAX, NULL, argv[0], cmdlines, args);

	/* Actually generate the cmdline array */
	cmdv = (char **)alloca((cmdc+1)*sizeof(char *));
	if (split_cmdline(cmdc, cmdv, argv[0], cmdlines, args) != cmdc) {
		ret = 1;
		goto bail;
	}

	/* Debugging... */
	dump_args(cmdc, cmdv);

	/* Resume from suspend-to-disk, if appropriate */
	/* If successful, does not return */
	do_resume(cmdc, cmdv);

	/* Initialize networking, if applicable */
	do_ipconfig(cmdc, cmdv);

	check_path("/root");
	do_mounts(cmdc, cmdv);

	if (mnt_procfs) {
		umount2("/proc", 0);
		mnt_procfs = 0;
	}

	if (mnt_sysfs) {
		umount2("/sys", 0);
		mnt_sysfs = 0;
	}

	init_path = find_init("/root", get_arg(cmdc, cmdv, "init="));
	if (!init_path) {
		fprintf(stderr, "%s: init not found!\n", progname);
		ret = 2;
		goto bail;
	}

	init_argv[0] = strrchr(init_path, '/') + 1;

	errmsg = run_init("/root", "/dev/console",
			  get_arg(cmdc, cmdv, "drop_capabilities="), false,
			  false, init_path, init_argv);

	/* If run_init returned, something went bad */
	fprintf(stderr, "%s: %s: %s\n", progname, errmsg, strerror(errno));
	ret = 2;
	goto bail;

bail:
	if (mnt_procfs)
		umount2("/proc", 0);

	if (mnt_sysfs)
		umount2("/sys", 0);

	/*
	 * If we get here, something bad probably happened, and the kernel
	 * will most likely panic.  Drain console output so the user can
	 * figure out what happened.
	 */
	tcdrain(2);
	tcdrain(1);

	return ret;
}
