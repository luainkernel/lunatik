/*
 * by tlh
 *
 * The uname program for system information: kernel name, kernel
 * release, kernel release, machine, processor, platform, os and
 * hostname.
 */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <sys/utsname.h>

enum uname_fields {
	UN_SYSNAME,
	UN_NODENAME,
	UN_RELEASE,
	UN_VERSION,
	UN_MACHINE,
#if NOT_IMPLEMENTED_PROCESSOR
	UN_PROCESSOR,
#endif
	UN_HARDWARE,
#if NOT_IMPLEMENTED_OS
	UN_OS,
#endif
	UN_NR_FIELDS
};

static void usage(FILE *stream, const char *progname)
{
	fprintf(stream,
		"Usage: %s [OPTION] . . .\n"
		"Print system information,  No options defaults to -s.\n"
		"\n"
		"  -a   print all the information in the same order as follows below\n"
		"  -s   kernel name\n"
		"  -n   network node name (hostname)\n"
		"  -r   kernel release\n"
		"  -v   kernel version\n" "  -m   machine hardware name\n"
#if NOT_IMPLEMENTED_PROCESSOR
		"  -p   processor type\n"
#endif
		"  -i   hardware platform\n"
#if NOT_IMPLEMENTED_OS
		"  -o   operating system\n"
#endif
		"\n" "  -h   help/usage\n" "\n", progname);
}

static char *make_hardware(const char *machine)
{
	char *hardware;

	hardware = strdup(machine);
	if (!hardware) {
		fprintf(stderr, "strdup() failed: %s\n", strerror(errno));
		goto end;
	}
	if (strlen(hardware) == 4
	    && hardware[0] == 'i' && hardware[2] == '8' && hardware[3] == '6') {
		hardware[1] = '3';
	}
end:
	return hardware;
}

int main(int argc, char *argv[])
{
	int ec = 1;
	int opt;
	int i;
	int nr_pr;
	struct utsname buf;
	char *uname_fields[UN_NR_FIELDS] = { NULL };

	if (-1 == uname(&buf)) {
		fprintf(stderr, "uname() failure: %s\n", strerror(errno));
		goto end;
	}

	if (1 == argc)
		/* no options given - default to -s */
		uname_fields[UN_SYSNAME] = buf.sysname;

	while ((opt = getopt(argc, argv, "asnrvmpioh")) != -1) {
		switch (opt) {
		case 'a':
			uname_fields[UN_SYSNAME] = buf.sysname;
			uname_fields[UN_NODENAME] = buf.nodename;
			uname_fields[UN_RELEASE] = buf.release;
			uname_fields[UN_VERSION] = buf.version;
			uname_fields[UN_MACHINE] = buf.machine;
			uname_fields[UN_HARDWARE] = make_hardware(buf.machine);
			if (!uname_fields[UN_HARDWARE])
				goto end;
			break;
		case 's':
			uname_fields[UN_SYSNAME] = buf.sysname;
			break;
		case 'n':
			uname_fields[UN_NODENAME] = buf.nodename;
			break;
		case 'r':
			uname_fields[UN_RELEASE] = buf.release;
			break;
		case 'v':
			uname_fields[UN_VERSION] = buf.version;
			break;
		case 'm':
			uname_fields[UN_MACHINE] = buf.machine;
			break;
#if NOT_IMPLEMENTED_PROCESSOR
		case 'p':
			break;
#endif
		case 'i':
			uname_fields[UN_HARDWARE] = make_hardware(buf.machine);
			if (!uname_fields[UN_HARDWARE])
				goto end;
			break;
#if NOT_IMPLEMENTED_OS
		case 'o':
			break;
#endif
		case 'h':
			usage(stdout, argv[0]);
			ec = 0;
			goto end;
			break;
		default:
			usage(stderr, argv[0]);
			goto end;
			break;
		}
	}

	for (nr_pr = 0, i = UN_SYSNAME; i < UN_NR_FIELDS; i++) {
		if (!uname_fields[i])
			continue;
		if (nr_pr)
			fputc(' ', stdout);
		fputs(uname_fields[i], stdout);
		nr_pr++;
	}
	fputc('\n', stdout);

	ec = 0;

end:
	if (uname_fields[UN_HARDWARE])
		free(uname_fields[UN_HARDWARE]);
	return ec;
}
