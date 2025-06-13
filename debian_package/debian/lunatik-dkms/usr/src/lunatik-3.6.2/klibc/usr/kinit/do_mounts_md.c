/*
 * Handle autoconfiguration of md devices.  This is ugly, partially since
 * it still relies on a sizable kernel component.
 *
 * This file is derived from the Linux kernel.
 */

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>
#include <sys/sysmacros.h>
#include <sys/md.h>
#include <linux/major.h>

#include "kinit.h"
#include "do_mounts.h"

#define  LEVEL_NONE              (-1000000)

/*
 * When md (and any require personalities) are compiled into the kernel
 * (not a module), arrays can be assembles are boot time using with AUTODETECT
 * where specially marked partitions are registered with md_autodetect_dev(),
 * and with MD_BOOT where devices to be collected are given on the boot line
 * with md=.....
 * The code for that is here.
 */

static int raid_noautodetect, raid_autopart;

static struct {
	int minor;
	int partitioned;
	int level;
	int chunk;
	char *device_names;
} md_setup_args[MAX_MD_DEVS];

static int md_setup_ents;

/**
 *	get_option - Parse integer from an option string
 *	@str: option string
 *	@pint: (output) integer value parsed from @str
 *
 *	Read an int from an option string; if available accept a subsequent
 *	comma as well.
 *
 *	Return values:
 *	0 : no int in string
 *	1 : int found, no subsequent comma
 *	2 : int found including a subsequent comma
 */

static int get_option(char **str, int *pint)
{
	char *cur = *str;

	if (!cur || !(*cur))
		return 0;
	*pint = strtol(cur, str, 0);
	if (cur == *str)
		return 0;
	if (**str == ',') {
		(*str)++;
		return 2;
	}

	return 1;
}

/*
 * Find the partitioned md device major number... of course this *HAD*
 * to be done dynamically instead of using a registered number.
 * Sigh.  Double sigh.
 */
static int mdp_major(void)
{
	static int found = 0;
	FILE *f;
	char line[512], *p;
	int is_blk, major_no;

	if (found)
		return found;

	f = fopen("/proc/devices", "r");
	is_blk = 0;
	while (fgets(line, sizeof line, f)) {
		if (!strcmp(line, "Block devices:\n"))
			is_blk = 1;
		if (is_blk) {
			major_no = strtol(line, &p, 10);
			while (*p && isspace(*p))
				p++;

			if (major_no == 0)	/* Not a number */
				is_blk = 0;
			else if (major_no > 0 && !strcmp(p, "mdp")) {
				found = major_no;
				break;
			}
		}
	}
	fclose(f);

	if (!found) {
		fprintf(stderr,
			"Error: mdp devices detected but no mdp device found!\n");
		exit(1);
	}

	return found;
}

/*
 * Parse the command-line parameters given our kernel, but do not
 * actually try to invoke the MD device now; that is handled by
 * md_setup_drive after the low-level disk drivers have initialised.
 *
 * 27/11/1999: Fixed to work correctly with the 2.3 kernel (which
 *             assigns the task of parsing integer arguments to the
 *             invoked program now).  Added ability to initialise all
 *             the MD devices (by specifying multiple "md=" lines)
 *             instead of just one.  -- KTK
 * 18May2000: Added support for persistent-superblock arrays:
 *             md=n,0,factor,fault,device-list   uses RAID0 for device n
 *             md=n,-1,factor,fault,device-list  uses LINEAR for device n
 *             md=n,device-list      reads a RAID superblock from the devices
 *             elements in device-list are read by name_to_kdev_t so can be
 *             a hex number or something like /dev/hda1 /dev/sdb
 * 2001-06-03: Dave Cinege <dcinege@psychosis.com>
 *		Shifted name_to_kdev_t() and related operations to md_set_drive()
 *		for later execution. Rewrote section to make devfs compatible.
 */
static int md_setup(char *str)
{
	int minor_num, level, factor, fault, partitioned = 0;
	char *pername = "";
	char *str1;
	int ent;

	if (*str == 'd') {
		partitioned = 1;
		str++;
	}
	if (get_option(&str, &minor_num) != 2) {	/* MD Number */
		fprintf(stderr, "md: Too few arguments supplied to md=.\n");
		return 0;
	}
	str1 = str;
	if (minor_num >= MAX_MD_DEVS) {
		fprintf(stderr, "md: md=%d, Minor device number too high.\n",
			minor_num);
		return 0;
	}
	for (ent = 0; ent < md_setup_ents; ent++)
		if (md_setup_args[ent].minor == minor_num &&
		    md_setup_args[ent].partitioned == partitioned) {
			fprintf(stderr,
				"md: md=%s%d, Specified more than once. "
				"Replacing previous definition.\n",
				partitioned ? "d" : "", minor_num);
			break;
		}
	if (ent >= MAX_MD_DEVS) {
		fprintf(stderr, "md: md=%s%d - too many md initialisations\n",
			partitioned ? "d" : "", minor_num);
		return 0;
	}
	if (ent >= md_setup_ents)
		md_setup_ents++;
	switch (get_option(&str, &level)) {	/* RAID level */
	case 2:		/* could be 0 or -1.. */
		if (level == 0 || level == LEVEL_LINEAR) {
			if (get_option(&str, &factor) != 2 ||	/* Chunk Size */
			    get_option(&str, &fault) != 2) {
				fprintf(stderr,
					"md: Too few arguments supplied to md=.\n");
				return 0;
			}
			md_setup_args[ent].level = level;
			md_setup_args[ent].chunk = 1 << (factor + 12);
			if (level == LEVEL_LINEAR)
				pername = "linear";
			else
				pername = "raid0";
			break;
		}
		/* FALL THROUGH */
	case 1:		/* the first device is numeric */
		str = str1;
		/* FALL THROUGH */
	case 0:
		md_setup_args[ent].level = LEVEL_NONE;
		pername = "super-block";
	}

	fprintf(stderr, "md: Will configure md%s%d (%s) from %s, below.\n",
		partitioned ? "_d" : "", minor_num, pername, str);
	md_setup_args[ent].device_names = str;
	md_setup_args[ent].partitioned = partitioned;
	md_setup_args[ent].minor = minor_num;

	return 1;
}

#define MdpMinorShift 6

static void md_setup_drive(void)
{
	int dev_minor, i, ent, partitioned;
	dev_t dev;
	dev_t devices[MD_SB_DISKS + 1];

	for (ent = 0; ent < md_setup_ents; ent++) {
		int fd;
		int err = 0;
		char *devname;
		mdu_disk_info_t dinfo;
		char name[16];
		struct stat st_chk;

		dev_minor = md_setup_args[ent].minor;
		partitioned = md_setup_args[ent].partitioned;
		devname = md_setup_args[ent].device_names;

		snprintf(name, sizeof name,
			 "/dev/md%s%d", partitioned ? "_d" : "", dev_minor);

		if (stat(name, &st_chk) == 0)
			continue;

		if (partitioned)
			dev = makedev(mdp_major(), dev_minor << MdpMinorShift);
		else
			dev = makedev(MD_MAJOR, dev_minor);
		create_dev(name, dev);
		for (i = 0; i < MD_SB_DISKS && devname != 0; i++) {
			char *p;

			p = strchr(devname, ',');
			if (p)
				*p++ = 0;

			dev = name_to_dev_t(devname);
			if (!dev) {
				fprintf(stderr, "md: Unknown device name: %s\n",
					devname);
				break;
			}

			devices[i] = dev;

			devname = p;
		}
		devices[i] = 0;

		if (!i)
			continue;

		fprintf(stderr, "md: Loading md%s%d: %s\n",
			partitioned ? "_d" : "", dev_minor,
			md_setup_args[ent].device_names);

		fd = open(name, 0, 0);
		if (fd < 0) {
			fprintf(stderr, "md: open failed - cannot start "
				"array %s\n", name);
			continue;
		}
		if (ioctl(fd, SET_ARRAY_INFO, 0) == -EBUSY) {
			fprintf(stderr,
				"md: Ignoring md=%d, already autodetected. (Use raid=noautodetect)\n",
				dev_minor);
			close(fd);
			continue;
		}

		if (md_setup_args[ent].level != LEVEL_NONE) {
			/* non-persistent */
			mdu_array_info_t ainfo;
			ainfo.level = md_setup_args[ent].level;
			ainfo.size = 0;
			ainfo.nr_disks = 0;
			ainfo.raid_disks = 0;
			while (devices[ainfo.raid_disks])
				ainfo.raid_disks++;
			ainfo.md_minor = dev_minor;
			ainfo.not_persistent = 1;

			ainfo.state = (1 << MD_SB_CLEAN);
			ainfo.layout = 0;
			ainfo.chunk_size = md_setup_args[ent].chunk;
			err = ioctl(fd, SET_ARRAY_INFO, &ainfo);
			for (i = 0; !err && i <= MD_SB_DISKS; i++) {
				dev = devices[i];
				if (!dev)
					break;
				dinfo.number = i;
				dinfo.raid_disk = i;
				dinfo.state =
				    (1 << MD_DISK_ACTIVE) | (1 << MD_DISK_SYNC);
				dinfo.major = major(dev);
				dinfo.minor = minor(dev);
				err = ioctl(fd, ADD_NEW_DISK, &dinfo);
			}
		} else {
			/* persistent */
			for (i = 0; i <= MD_SB_DISKS; i++) {
				dev = devices[i];
				if (!dev)
					break;
				dinfo.major = major(dev);
				dinfo.minor = minor(dev);
				ioctl(fd, ADD_NEW_DISK, &dinfo);
			}
		}
		if (!err)
			err = ioctl(fd, RUN_ARRAY, 0);
		if (err)
			fprintf(stderr, "md: starting md%d failed\n",
				dev_minor);
		else {
			/* reread the partition table.
			 * I (neilb) and not sure why this is needed, but I
			 * cannot boot a kernel with devfs compiled in from
			 * partitioned md array without it
			 */
			close(fd);
			fd = open(name, 0, 0);
			ioctl(fd, BLKRRPART, 0);
		}
		close(fd);
	}
}

static int raid_setup(char *str)
{
	int len, pos;

	len = strlen(str) + 1;
	pos = 0;

	while (pos < len) {
		char *comma = strchr(str + pos, ',');
		int wlen;
		if (comma)
			wlen = (comma - str) - pos;
		else
			wlen = (len - 1) - pos;

		if (!strncmp(str, "noautodetect", wlen))
			raid_noautodetect = 1;
		if (strncmp(str, "partitionable", wlen) == 0)
			raid_autopart = 1;
		if (strncmp(str, "part", wlen) == 0)
			raid_autopart = 1;
		pos += wlen + 1;
	}
	return 1;
}

static void md_run_setup(void)
{
	create_dev("/dev/md0", makedev(MD_MAJOR, 0));
	if (raid_noautodetect)
		fprintf(stderr,
			"md: Skipping autodetection of RAID arrays. (raid=noautodetect)\n");
	else {
		int fd = open("/dev/md0", 0, 0);
		if (fd >= 0) {
			ioctl(fd, RAID_AUTORUN,
			      (void *)(intptr_t) raid_autopart);
			close(fd);
		}
	}
	md_setup_drive();
}

void md_run(int argc, char *argv[])
{
	char **pp, *p;

	for (pp = argv; (p = *pp); pp++) {
		if (!strncmp(p, "raid=", 5))
			raid_setup(p + 5);
		else if (!strncmp(p, "md=", 3))
			md_setup(p + 3);
	}

	md_run_setup();
}
