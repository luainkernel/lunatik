/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Userspace peer for the hid device test (see device.sh): creates a uhid device
* for each product given, and for each one a driver binds prints the report
* descriptor the device then has, sends it the reports whose first byte is 0 to
* 6, the last one <count> times, and prints those its hidraw node received:
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
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/uhid.h>

#define BUS		0x03	/* BUS_USB */
#define VENDOR		0xf055	/* no device on the hid bus carries it, so only the test's driver binds */
#define BIND_MS		2000
#define DRAIN_MS	500
#define NREPORTS	7
#define MAXDEVS		8
#define BIND		"bind@"	/* the uevent's action, followed by the device's path under /sys */

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
	int bound;
	char sysfs[PATH_MAX];
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

static int subscribe(void)
{
	struct sockaddr_nl addr = {.nl_family = AF_NETLINK, .nl_groups = 1};	/* the kernel's own uevents */
	int fd = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_KOBJECT_UEVENT);

	if (fd >= 0 && bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

/* a bind is sent once the probe returned: a report sent during the probe finds the input lock taken */
static void match(peer_t *peers, int n, const char *uevent)
{
	const char *name = strrchr(uevent, '/');
	char prefix[sizeof("BBBB:VVVV:PPPP.")];
	int i;

	if (strncmp(uevent, BIND, strlen(BIND)) != 0 || name == NULL)
		return;
	for (i = 0; i < n; i++) {
		snprintf(prefix, sizeof(prefix), "%04X:%04X:%04X.", BUS, VENDOR, peers[i].product);
		if (strncmp(name + 1, prefix, strlen(prefix)) == 0) {
			snprintf(peers[i].sysfs, sizeof(peers[i].sysfs), "/sys%s", uevent + strlen(BIND));
			peers[i].bound = 1;
		}
	}
}

static int elapsed(const struct timespec *start)
{
	struct timespec now;

	clock_gettime(CLOCK_MONOTONIC, &now);
	return (now.tv_sec - start->tv_sec) * 1000 + (now.tv_nsec - start->tv_nsec) / 1000000;
}

static int pending(peer_t *peers, int n)
{
	int i, count = 0;

	for (i = 0; i < n; i++)
		count += !peers[i].bound;
	return count;
}

static void await(int uevents, peer_t *peers, int n)
{
	struct pollfd pfd = {.fd = uevents, .events = POLLIN};
	char uevent[PATH_MAX];
	struct timespec start;
	int waited;

	clock_gettime(CLOCK_MONOTONIC, &start);
	while ((waited = elapsed(&start)) < BIND_MS && pending(peers, n) && poll(&pfd, 1, BIND_MS - waited) > 0) {
		ssize_t len = recv(uevents, uevent, sizeof(uevent) - 1, 0);

		if (len > 0) {
			uevent[len] = '\0';
			match(peers, n, uevent);
		}
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
	int opt, i, uevents;

	while ((opt = getopt(argc, argv, "r:")) != -1) {
		if (opt != 'r')
			return 2;
		count = atoi(optarg);
	}

	if ((uevents = subscribe()) < 0) {
		perror("uevent socket");
		return 1;
	}
	for (i = optind; i < argc && n < MAXDEVS; i++, n++) {
		peers[n].product = strtoul(argv[i], NULL, 16);
		peers[n].bound = 0;
		if ((peers[n].uhid = create(peers[n].product)) < 0) {
			perror("uhid create");
			return 1;
		}
	}

	await(uevents, peers, n);
	close(uevents);
	for (i = 0; i < n; i++) {
		if (!peers[i].bound) {
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

