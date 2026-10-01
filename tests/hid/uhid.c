/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Userspace peer for the hid device test (see device.sh): creates a uhid device
* for each product given, and for each one a driver binds prints the report
* descriptor the device then has, sends it the reports whose first byte is 0 to
* 4, the last one <count> times, and prints those its hidraw node received:
* "<product> rdesc <bytes>", "<product> report <bytes>", or "<product> unbound".
* It then prints "ready" and holds the devices until it is killed.
*
* Usage: uhid [-r <count>] <product>...
*/

#include <fcntl.h>
#include <glob.h>
#include <limits.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <linux/uhid.h>

#define BUS		0x03	/* BUS_USB */
#define VENDOR		0xf055	/* no device on the hid bus carries it, so only the test's driver binds */
#define BIND_MS		2000
#define STEP_MS		50
#define DRAIN_MS	500
#define NREPORTS	5
#define MAXDEVS		8
#define SYSFS_MAX	128	/* /sys/bus/hid/devices/BBBB:VVVV:PPPP.NNNN */

static const unsigned char rdesc[] = {
	0x06, 0x00, 0xff,	/* Usage Page (Vendor Defined 0xff00) */
	0x09, 0x01,		/* Usage (0x01) */
	0xa1, 0x01,		/* Collection (Application) */
	0x09, 0x02,		/* Usage (0x02) */
	0x15, 0x00,		/* Logical Minimum (0) */
	0x26, 0xff, 0x00,	/* Logical Maximum (255) */
	0x75, 0x08,		/* Report Size (8) */
	0x95, 0x02,		/* Report Count (2) */
	0x81, 0x02,		/* Input (Data, Variable, Absolute) */
	0xc0,			/* End Collection */
};

typedef struct peer_s {
	unsigned int product;
	int uhid;
	char sysfs[SYSFS_MAX];
} peer_t;

static int create(unsigned int product)
{
	struct uhid_event ev;
	int fd = open("/dev/uhid", O_RDWR | O_CLOEXEC);

	if (fd < 0)
		return -1;

	memset(&ev, 0, sizeof(ev));
	ev.type = UHID_CREATE2;
	snprintf((char *)ev.u.create2.name, sizeof(ev.u.create2.name), "lunatik_hid_%04x", product);
	memcpy(ev.u.create2.rd_data, rdesc, sizeof(rdesc));
	ev.u.create2.rd_size = sizeof(rdesc);
	ev.u.create2.bus = BUS;
	ev.u.create2.vendor = VENDOR;
	ev.u.create2.product = product;
	if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) {
		close(fd);
		return -1;
	}
	return fd;
}

/* linked once the probe returned: a report sent during the probe finds the input lock taken */
static int bound(peer_t *peer)
{
	char pattern[PATH_MAX], driver[PATH_MAX];
	glob_t found;

	snprintf(pattern, sizeof(pattern), "/sys/bus/hid/devices/%04X:%04X:%04X.*", BUS, VENDOR, peer->product);
	if (glob(pattern, 0, NULL, &found) != 0)
		return 0;
	snprintf(peer->sysfs, sizeof(peer->sysfs), "%s", found.gl_pathv[0]);
	globfree(&found);

	snprintf(driver, sizeof(driver), "%s/driver", peer->sysfs);
	return access(driver, F_OK) == 0;
}

static void await(peer_t *peers, int n)
{
	struct timespec step = {0, STEP_MS * 1000000L};
	int waited, i, pending;

	for (waited = 0; waited < BIND_MS; waited += STEP_MS) {
		for (i = 0, pending = 0; i < n; i++)
			pending += !bound(&peers[i]);
		if (pending == 0)
			return;
		nanosleep(&step, NULL);
	}
}

static void printbytes(const unsigned char *bytes, ssize_t n)
{
	ssize_t i;

	for (i = 0; i < n; i++)
		printf(" %02x", bytes[i]);
	printf("\n");
}

static void printrdesc(peer_t *peer)
{
	char path[PATH_MAX];
	unsigned char buf[HID_MAX_DESCRIPTOR_SIZE];
	ssize_t n;
	int fd;

	snprintf(path, sizeof(path), "%s/report_descriptor", peer->sysfs);
	if ((fd = open(path, O_RDONLY)) < 0)
		return;
	n = read(fd, buf, sizeof(buf));
	close(fd);
	printf("%04x rdesc", peer->product);
	printbytes(buf, n < 0 ? 0 : n);
}

static int openhidraw(peer_t *peer)
{
	char pattern[PATH_MAX], node[PATH_MAX];
	glob_t found;

	snprintf(pattern, sizeof(pattern), "%s/hidraw/hidraw*", peer->sysfs);
	if (glob(pattern, 0, NULL, &found) != 0)
		return -1;
	snprintf(node, sizeof(node), "/dev/%s", strrchr(found.gl_pathv[0], '/') + 1);
	globfree(&found);
	return open(node, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
}

static void input(int uhid, unsigned char byte)
{
	struct uhid_event ev;

	memset(&ev, 0, sizeof(ev));
	ev.type = UHID_INPUT2;
	ev.u.input2.size = 2;
	ev.u.input2.data[0] = byte;
	ev.u.input2.data[1] = byte;
	if (write(uhid, &ev, sizeof(ev)) != sizeof(ev))
		perror("uhid input");
}

static void drain(peer_t *peer, int hidraw)
{
	struct pollfd pfd = {.fd = hidraw, .events = POLLIN};
	unsigned char buf[UHID_DATA_MAX];
	ssize_t n;

	while (poll(&pfd, 1, DRAIN_MS) > 0 && (n = read(hidraw, buf, sizeof(buf))) > 0) {
		printf("%04x report", peer->product);
		printbytes(buf, n);
	}
}

static void drive(peer_t *peer, int count)
{
	int hidraw = openhidraw(peer);
	int byte, i;

	if (hidraw < 0) {
		printf("%04x nohidraw\n", peer->product);
		return;
	}
	for (byte = 0; byte < NREPORTS - 1; byte++)
		input(peer->uhid, byte);
	for (i = 0; i < count; i++)
		input(peer->uhid, NREPORTS - 1);
	drain(peer, hidraw);
	close(hidraw);
}

int main(int argc, char *argv[])
{
	peer_t peers[MAXDEVS];
	int count = 1;
	int n = 0;
	int opt, i;

	while ((opt = getopt(argc, argv, "r:")) != -1) {
		if (opt != 'r')
			return 2;
		count = atoi(optarg);
	}

	for (i = optind; i < argc && n < MAXDEVS; i++, n++) {
		peers[n].product = strtoul(argv[i], NULL, 16);
		if ((peers[n].uhid = create(peers[n].product)) < 0) {
			perror("uhid create");
			return 1;
		}
	}

	await(peers, n);
	for (i = 0; i < n; i++) {
		if (!bound(&peers[i])) {
			printf("%04x unbound\n", peers[i].product);
			continue;
		}
		printrdesc(&peers[i]);
		drive(&peers[i], count);
	}

	printf("ready\n");
	fflush(stdout);
	pause();
	return 0;
}

