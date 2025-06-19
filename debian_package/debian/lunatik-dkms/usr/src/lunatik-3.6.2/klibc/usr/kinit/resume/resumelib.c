/*
 * Handle resume from suspend-to-disk
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

#include "kinit.h"
#include "do_mounts.h"
#include "resume.h"

#ifndef CONFIG_PM_STD_PARTITION
# define CONFIG_PM_STD_PARTITION ""
#endif

int do_resume(int argc, char *argv[])
{
	const char *resume_file = CONFIG_PM_STD_PARTITION;
	const char *resume_arg;
	unsigned long long resume_offset;

	resume_arg = get_arg(argc, argv, "resume=");
	resume_file = resume_arg ? resume_arg : resume_file;
	/* No resume device specified */
	if (!resume_file[0])
		return 0;

	resume_arg = get_arg(argc, argv, "resume_offset=");
	resume_offset = resume_arg ? strtoull(resume_arg, NULL, 0) : 0ULL;

	/* Fix: we either should consider reverting the device back to
	   ordinary swap, or (better) put that code into swapon */
	/* Noresume requested */
	if (get_flag(argc, argv, "noresume"))
		return 0;
	return resume(resume_file, resume_offset);
}

int resume(const char *resume_file, unsigned long long resume_offset)
{
	dev_t resume_device;
	int attr_fd = -1;
	char attr_value[64];
	int len;

	resume_device = name_to_dev_t(resume_file);

	if (major(resume_device) == 0) {
		fprintf(stderr, "Invalid resume device: %s\n", resume_file);
		goto failure;
	}

	if ((attr_fd = open("/sys/power/resume_offset", O_WRONLY)) < 0)
		goto fail_offset;

	len = snprintf(attr_value, sizeof attr_value,
		       "%llu",
		       resume_offset);

	/* This should never happen */
	if (len >= sizeof attr_value)
		goto fail_offset;

	if (write(attr_fd, attr_value, len) != len)
		goto fail_offset;

	close(attr_fd);

	if ((attr_fd = open("/sys/power/resume", O_WRONLY)) < 0)
		goto fail_r;

	len = snprintf(attr_value, sizeof attr_value,
		       "%u:%u",
		       major(resume_device), minor(resume_device));

	/* This should never happen */
	if (len >= sizeof attr_value)
		goto fail_r;

	dprintf("kinit: trying to resume from %s\n", resume_file);

	if (write(attr_fd, attr_value, len) != len)
		goto fail_r;

	/* Okay, what are we still doing alive... */
failure:
	if (attr_fd >= 0)
		close(attr_fd);
	dprintf("kinit: No resume image, doing normal boot...\n");
	return -1;

fail_offset:
	fprintf(stderr, "Cannot write /sys/power/resume_offset "
			"(no software suspend kernel support, or old kernel version?)\n");
	goto failure;

fail_r:
	fprintf(stderr, "Cannot write /sys/power/resume "
			"(no software suspend kernel support?)\n");
	goto failure;
}
