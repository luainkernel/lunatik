/*
 * Copyright 2011 Google Inc. All Rights Reserved
 * Author: mikew@google.com (Mike Waychison)
 */

/*
 * We have to include the klibc types.h here to keep the kernel's
 * types.h from being used.
 */
#include <sys/types.h>

#include <sys/capability.h>
#include <sys/prctl.h>
#include <sys/utsname.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "kinit.h"

#define ARRAY_SIZE(x)  (sizeof(x) / sizeof(x[0]))

#define MAKE_CAP(cap) [cap] = { .cap_name = #cap }

struct capability {
	const char *cap_name;
} capabilities[] = {
	MAKE_CAP(CAP_CHOWN),
	MAKE_CAP(CAP_DAC_OVERRIDE),
	MAKE_CAP(CAP_DAC_READ_SEARCH),
	MAKE_CAP(CAP_FOWNER),
	MAKE_CAP(CAP_FSETID),
	MAKE_CAP(CAP_KILL),
	MAKE_CAP(CAP_SETGID),
	MAKE_CAP(CAP_SETUID),
	MAKE_CAP(CAP_SETPCAP),
	MAKE_CAP(CAP_LINUX_IMMUTABLE),
	MAKE_CAP(CAP_NET_BIND_SERVICE),
	MAKE_CAP(CAP_NET_BROADCAST),
	MAKE_CAP(CAP_NET_ADMIN),
	MAKE_CAP(CAP_NET_RAW),
	MAKE_CAP(CAP_IPC_LOCK),
	MAKE_CAP(CAP_IPC_OWNER),
	MAKE_CAP(CAP_SYS_MODULE),
	MAKE_CAP(CAP_SYS_RAWIO),
	MAKE_CAP(CAP_SYS_CHROOT),
	MAKE_CAP(CAP_SYS_PTRACE),
	MAKE_CAP(CAP_SYS_PACCT),
	MAKE_CAP(CAP_SYS_ADMIN),
	MAKE_CAP(CAP_SYS_BOOT),
	MAKE_CAP(CAP_SYS_NICE),
	MAKE_CAP(CAP_SYS_RESOURCE),
	MAKE_CAP(CAP_SYS_TIME),
	MAKE_CAP(CAP_SYS_TTY_CONFIG),
	MAKE_CAP(CAP_MKNOD),
	MAKE_CAP(CAP_LEASE),
	MAKE_CAP(CAP_AUDIT_WRITE),
	MAKE_CAP(CAP_AUDIT_CONTROL),
	MAKE_CAP(CAP_SETFCAP),
	MAKE_CAP(CAP_MAC_OVERRIDE),
	MAKE_CAP(CAP_MAC_ADMIN),
	MAKE_CAP(CAP_SYSLOG),
};

static void fail(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void fail(const char *fmt, ...)
{
	va_list args;

	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	exit(1);
}

/*
 * Find the capability ordinal by name, and return its ordinal.
 * Returns -1 on failure.
 */
static int find_capability(const char *s)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(capabilities); i++) {
		if (capabilities[i].cap_name
		 && strcasecmp(s, capabilities[i].cap_name) == 0) {
			return i;
		}
	}
	return -1;
}

static void do_capset(int cap_ordinal)
{
	struct __user_cap_header_struct hdr;
	struct __user_cap_data_struct caps[2];

	/* Get the current capability mask */
	hdr.version = _LINUX_CAPABILITY_VERSION_3;
	hdr.pid = getpid();
	if (capget(&hdr, caps)) {
		perror("capget()");
		exit(1);
	}

	/* Drop the bits */
	if (cap_ordinal < 32)
		caps[0].inheritable &= ~(1U << cap_ordinal);
	else
		caps[1].inheritable &= ~(1U << (cap_ordinal - 32));

	/* And drop the capability. */
	hdr.version = _LINUX_CAPABILITY_VERSION_3;
	hdr.pid = getpid();
	if (capset(&hdr, caps))
		fail("Couldn't drop the capability \"%s\"\n",
		     capabilities[cap_ordinal].cap_name);
}

static void do_bset(int cap_ordinal)
{
	int ret;

	ret = prctl(PR_CAPBSET_READ, cap_ordinal);
	if (ret == 1) {
		ret = prctl(PR_CAPBSET_DROP, cap_ordinal);
		if (ret != 0)
			fail("Error dropping capability %s from bset\n",
			     capabilities[cap_ordinal].cap_name);
	} else if (ret < 0)
		fail("Kernel doesn't recognize capability %d\n", cap_ordinal);
}

static void do_usermodehelper_file(const char *filename, int cap_ordinal)
{
	uint32_t lo32, hi32;
	FILE *file;
	static const size_t buf_size = 80;
	char buf[buf_size];
	char tail;
	size_t bytes_read;
	int ret;

	/* Try and open the file */
	file = fopen(filename, "r+");
	if (!file && errno == ENOENT)
		fail("Could not disable usermode helpers capabilities as "
		     "%s is not available\n", filename);
	if (!file)
		fail("Failed to access file %s errno %d\n", filename, errno);

	/* Read and process the current bits */
	bytes_read = fread(buf, 1, buf_size - 1, file);
	if (bytes_read == 0)
		fail("Trouble reading %s\n", filename);
	buf[bytes_read] = '\0';
	ret = sscanf(buf, "%u %u %c", &lo32, &hi32, &tail);
	if (ret != 2)
		fail("Failed to understand %s \"%s\"\n", filename, buf);

	/* Clear the bits in the local copy */
	if (cap_ordinal < 32)
		lo32 &= ~(1 << cap_ordinal);
	else
		hi32 &= ~(1 << (cap_ordinal - 32));

	/* Commit the new bit masks to the kernel */
	ret = fflush(file);
	if (ret != 0)
		fail("Failed on file %s to fflush %d\n", filename, ret);
	sprintf(buf, "%u %u", lo32, hi32);
	ret = fwrite(buf, 1, strlen(buf) + 1, file);
	if (ret != 0)
		fail("Failed to commit usermode helper bitmasks: %d\n", ret);

	/* Cleanup */
	fclose(file);
}

static void do_usermodehelper(int cap_ordinal)
{
	static const char * const files[] = {
		"/proc/sys/kernel/usermodehelper/bset",
		"/proc/sys/kernel/usermodehelper/inheritable",
	};
	int i;

	for (i = 0; i < ARRAY_SIZE(files); i++)
		do_usermodehelper_file(files[i], cap_ordinal);
}

static void drop_capability(int cap_ordinal)
{
	do_usermodehelper(cap_ordinal);
	do_bset(cap_ordinal);
	do_capset(cap_ordinal);

	printf("Dropped capability: %s\n", capabilities[cap_ordinal].cap_name);
}

int drop_capabilities(const char *caps)
{
	char *s, *saveptr = NULL;
	char *token;

	if (!caps)
		return 0;

	/* Create a duplicate string that can be modified. */
	s = strdup(caps);
	if (!s)
		fail("Failed to drop caps as requested.  Exiting\n");

	token = strtok_r(s, ",", &saveptr);
	while (token) {
		int cap_ordinal = find_capability(token);

		if (cap_ordinal < 0)
			fail("Could not understand capability name \"%s\" "
			     "on command line, failing init\n", token);

		drop_capability(cap_ordinal);

		token = strtok_r(NULL, ",", &saveptr);
	}

	free(s);
	return 0;
}
