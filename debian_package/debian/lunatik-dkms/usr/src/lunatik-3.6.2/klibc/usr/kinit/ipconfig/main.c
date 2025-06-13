#include <poll.h>
#include <limits.h>
#include <setjmp.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/sysinfo.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>		/* for getopts */

#include <net/if_arp.h>

#include "ipconfig.h"
#include "netdev.h"
#include "bootp_packet.h"
#include "bootp_proto.h"
#include "dhcp_proto.h"
#include "packet.h"

static const char sysfs_class_net[] = "/sys/class/net";
static const char *progname;
static jmp_buf abort_buf;
static char do_not_config;
static unsigned int default_caps = CAP_DHCP | CAP_BOOTP | CAP_RARP;
static int loop_timeout = -1;
static int configured;
static int bringup_first = 0;
static int n_devices = 0;

/* DHCP vendor class identifier */
char vendor_class_identifier[260];
int vendor_class_identifier_len;

struct state {
	int state;
	int restart_state;
	time_t expire;
	int retry_period;

	struct netdev *dev;
	struct state *next;
};

/* #define PROTO_x : for uint8_t proto of struct netdev */
struct protoinfo {
	char *name;
} protoinfos[] = {
#define PROTO_NONE  0
	{"none"},
#define PROTO_BOOTP 1
	{"bootp"},
#define PROTO_DHCP  2
	{"dhcp"},
#define PROTO_RARP  3
	{"rarp"}
};

static inline const char *my_inet_ntoa(uint32_t addr)
{
	struct in_addr a;

	a.s_addr = addr;

	return inet_ntoa(a);
}

static void print_device_config(struct netdev *dev)
{
	int dns0_spaces;
	int dns1_spaces;
	printf("IP-Config: %s complete", dev->name);
	if (dev->proto == PROTO_BOOTP || dev->proto == PROTO_DHCP)
		printf(" (%s from %s)", protoinfos[dev->proto].name,
		       my_inet_ntoa(dev->serverid ?
				    dev->serverid : dev->ip_server));

	printf(":\n address: %-16s ", my_inet_ntoa(dev->ip_addr));
	printf("broadcast: %-16s ", my_inet_ntoa(dev->ip_broadcast));
	printf("netmask: %-16s\n", my_inet_ntoa(dev->ip_netmask));
	if (dev->routes != NULL) {
		struct route *cur;
		char *delim = "";
		printf(" routes :");
		for (cur = dev->routes; cur != NULL; cur = cur->next) {
			printf("%s %s/%u", delim, my_inet_ntoa(cur->subnet), cur->netmask_width);
			if (cur->gateway != 0) {
				printf(" via %s", my_inet_ntoa(cur->gateway));
			}
			delim = ",";
		}
		printf("\n");
		dns0_spaces = 3;
		dns1_spaces = 5;
	} else {
		printf(" gateway: %-16s", my_inet_ntoa(dev->ip_gateway));
		dns0_spaces = 5;
		dns1_spaces = 3;
	}
	printf(" dns0%*c: %-16s", dns0_spaces, ' ', my_inet_ntoa(dev->ip_nameserver[0]));
	printf(" dns1%*c: %-16s\n", dns1_spaces, ' ', my_inet_ntoa(dev->ip_nameserver[1]));
	if (dev->hostname[0])
		printf(" host   : %-64s\n", dev->hostname);
	if (dev->dnsdomainname[0])
		printf(" domain : %-64s\n", dev->dnsdomainname);
	if (dev->nisdomainname[0])
		printf(" nisdomain: %-64s\n", dev->nisdomainname);
	printf(" rootserver: %s ", my_inet_ntoa(dev->ip_server));
	printf("rootpath: %s\n", dev->bootpath);
	printf(" filename  : %s\n", dev->filename);
}

static void configure_device(struct netdev *dev)
{
	if (do_not_config)
		return;

	if (netdev_setmtu(dev))
		printf("IP-Config: failed to set MTU on %s to %u\n",
		       dev->name, dev->mtu);

	if (netdev_setaddress(dev))
		printf("IP-Config: failed to set addresses on %s\n",
		       dev->name);
	if (netdev_setroutes(dev))
		printf("IP-Config: failed to set routes on %s\n",
		       dev->name);
	if (dev->hostname[0] &&
			sethostname(dev->hostname, strlen(dev->hostname)))
		printf("IP-Config: failed to set hostname '%s' from %s\n",
			dev->hostname, dev->name);
}

/*
 * Escape shell varialbes in git style:
 * Always start with a single quote ('), then leave all characters
 * except ' and ! unchanged.
 */
static void write_option(FILE *f, const char *name, const char *chr)
{

	fprintf(f, "%s='", name);
	while (*chr) {
		switch (*chr) {
		case '!':
		case '\'':
			fprintf(f, "'\\%c'", *chr);
			break;
		default:
			fprintf(f, "%c", *chr);
			break;
		}
		++chr;
	}
	fprintf(f, "'\n");
}

static void dump_device_config(struct netdev *dev)
{
	char fn[40];
	FILE *f;
	/*
	 * char UINT64_MAX[] = "18446744073709551615";
	 * sizeof(UINT64_MAX)==21
	 */
	char buf21[21];
	const char path[] = "/run/";

	snprintf(fn, sizeof(fn), "%snet-%s.conf", path, dev->name);
	f = fopen(fn, "w");
	if (f) {
		write_option(f, "DEVICE", dev->name);
		write_option(f, "PROTO", protoinfos[dev->proto].name);
		write_option(f, "IPV4ADDR",
				my_inet_ntoa(dev->ip_addr));
		write_option(f, "IPV4BROADCAST",
				my_inet_ntoa(dev->ip_broadcast));
		write_option(f, "IPV4NETMASK",
				my_inet_ntoa(dev->ip_netmask));
		if (dev->routes != NULL) {
			/* Use 6 digits to encode the index */
			char key[23];
			char value[19];
			int i = 0;
			struct route *cur;
			for (cur = dev->routes; cur != NULL; cur = cur->next) {
				snprintf(key, sizeof(key), "IPV4ROUTE%iSUBNET", i);
				snprintf(value, sizeof(value), "%s/%u", my_inet_ntoa(cur->subnet), cur->netmask_width);
				write_option(f, key, value);
				snprintf(key, sizeof(key), "IPV4ROUTE%iGATEWAY", i);
				write_option(f, key, my_inet_ntoa(cur->gateway));
				i++;
			}
		} else {
			write_option(f, "IPV4GATEWAY",
					my_inet_ntoa(dev->ip_gateway));
		}
		write_option(f, "IPV4DNS0",
				my_inet_ntoa(dev->ip_nameserver[0]));
		write_option(f, "IPV4DNS1",
				my_inet_ntoa(dev->ip_nameserver[1]));
		write_option(f, "HOSTNAME",  dev->hostname);
		write_option(f, "DNSDOMAIN", dev->dnsdomainname);
		write_option(f, "NISDOMAIN", dev->nisdomainname);
		write_option(f, "ROOTSERVER",
				my_inet_ntoa(dev->ip_server));
		write_option(f, "ROOTPATH", dev->bootpath);
		write_option(f, "filename", dev->filename);
		sprintf(buf21, "%ld", (long)dev->uptime);
		write_option(f, "UPTIME", buf21);
		sprintf(buf21, "%u", (unsigned int)dev->dhcpleasetime);
		write_option(f, "DHCPLEASETIME", buf21);
		write_option(f, "DOMAINSEARCH", dev->domainsearch == NULL ?
			     "" : dev->domainsearch);
		fclose(f);
	}
}

static uint32_t inet_class_netmask(uint32_t ip)
{
	ip = ntohl(ip);
	if (IN_CLASSA(ip))
		return htonl(IN_CLASSA_NET);
	if (IN_CLASSB(ip))
		return htonl(IN_CLASSB_NET);
	if (IN_CLASSC(ip))
		return htonl(IN_CLASSC_NET);
	return INADDR_ANY;
}

static void postprocess_device(struct netdev *dev)
{
	if (dev->ip_netmask == INADDR_ANY) {
		dev->ip_netmask = inet_class_netmask(dev->ip_addr);
		printf("IP-Config: %s guessed netmask %s\n",
		       dev->name, my_inet_ntoa(dev->ip_netmask));
	}
	if (dev->ip_broadcast == INADDR_ANY) {
		dev->ip_broadcast =
		    (dev->ip_addr & dev->ip_netmask) | ~dev->ip_netmask;
		printf("IP-Config: %s guessed broadcast address %s\n",
		       dev->name, my_inet_ntoa(dev->ip_broadcast));
	}
}

static void complete_device(struct netdev *dev)
{
	struct sysinfo info;

	if (!sysinfo(&info))
		dev->uptime = info.uptime;
	postprocess_device(dev);
	configure_device(dev);
	dump_device_config(dev);
	print_device_config(dev);
	packet_close(dev);

	++configured;

	dev->next = ifaces;
	ifaces = dev;
}

/*
 * Returns:
 *  0 = Not handled, try again later
 *  1 = Handled
 */
static int process_receive_event(struct state *s, time_t now)
{
	int handled = 1;

	switch (s->state) {
	case DEVST_ERROR:
		return 0; /* Not handled */
	case DEVST_COMPLETE:
		return 0; /* Not handled as already configured */

	case DEVST_BOOTP:
		s->restart_state = DEVST_BOOTP;
		switch (bootp_recv_reply(s->dev)) {
		case -1:
			s->state = DEVST_ERROR;
			break;
		case 0:
			handled = 0;
			break;
		case 1:
			s->state = DEVST_COMPLETE;
			s->dev->proto = PROTO_BOOTP;
			dprintf("\n   bootp reply\n");
			break;
		}
		break;

	case DEVST_DHCPDISC:
		s->restart_state = DEVST_DHCPDISC;
		switch (dhcp_recv_offer(s->dev)) {
		case -1:
			s->state = DEVST_ERROR;
			break;
		case 0:
			handled = 0;
			break;
		case DHCPOFFER:	/* Offer received */
			s->state = DEVST_DHCPREQ;
			dhcp_send_request(s->dev);
			break;
		}
		break;

	case DEVST_DHCPREQ:
		s->restart_state = DEVST_DHCPDISC;
		switch (dhcp_recv_ack(s->dev)) {
		case -1:	/* error */
			s->state = DEVST_ERROR;
			break;
		case 0:
			handled = 0;
			break;
		case DHCPACK:	/* ACK received */
			s->state = DEVST_COMPLETE;
			s->dev->proto = PROTO_DHCP;
			break;
		case DHCPNAK:	/* NAK received */
			s->state = DEVST_DHCPDISC;
			break;
		}
		break;

	default:
		dprintf("\n");
		handled = 0;
		break;
	}

	switch (s->state) {
	case DEVST_COMPLETE:
		complete_device(s->dev);
		break;

	case DEVST_ERROR:
		/* error occurred, try again in 10 seconds */
		s->expire = now + 10;
		break;
	}

	return handled;
}

static void process_timeout_event(struct state *s, time_t now)
{
	int ret = 0;

	/*
	 * If we had an error, restore a sane state to
	 * restart from.
	 */
	if (s->state == DEVST_ERROR)
		s->state = s->restart_state;

	/*
	 * Now send a packet depending on our state.
	 */
	switch (s->state) {
	case DEVST_BOOTP:
		ret = bootp_send_request(s->dev);
		s->restart_state = DEVST_BOOTP;
		break;

	case DEVST_DHCPDISC:
		ret = dhcp_send_discover(s->dev);
		s->restart_state = DEVST_DHCPDISC;
		break;

	case DEVST_DHCPREQ:
		ret = dhcp_send_request(s->dev);
		s->restart_state = DEVST_DHCPDISC;
		break;
	}

	if (ret == -1) {
		s->state = DEVST_ERROR;
		s->expire = now + 1;
	} else {
		s->expire = now + s->retry_period;

		s->retry_period *= 2;
		if (s->retry_period > 60)
			s->retry_period = 60;
	}
}

static void process_error_event(struct state *s, time_t now)
{
	s->state = DEVST_ERROR;
	s->expire = now + 1;
}

static struct state *slist;
struct netdev *ifaces;

/*
 * Returns:
 *  0 = No dhcp/bootp packet was received
 *  1 = A packet was received and handled
 */
static int do_pkt_recv(int nr, struct pollfd *fds, time_t now)
{
	int i, ret = 0;
	struct state *s;

	for (i = 0, s = slist; s && nr; s = s->next) {
		if (s->dev->pkt_fd != fds[i].fd)
			continue;
		if (fds[i].revents) {
			if (fds[i].revents & POLLRDNORM)
				ret |= process_receive_event(s, now);
			else
				process_error_event(s, now);
			nr--;
		}
		i++;
	}
	return ret;
}

static int loop(void)
{
	struct pollfd *fds;
	struct state *s;
	int i, nr = 0, rc = 0;
	struct timeval now, prev;
	time_t start;

	fds = malloc(sizeof(struct pollfd) * n_devices);
	if (!fds) {
		fprintf(stderr, "malloc failed\n");
		rc = -1;
		goto bail;
	}

	memset(fds, 0, sizeof(*fds));

	gettimeofday(&now, NULL);
	start = now.tv_sec;
	while (1) {
		int timeout = 60;
		int pending = 0;
		int done = 0;
		int timeout_ms;
		int x;

		for (i = 0, s = slist; s; s = s->next) {
			dprintf("%s: state = %d\n", s->dev->name, s->state);

			if (s->state == DEVST_COMPLETE) {
				done++;
				continue;
			}

			pending++;

			if (s->expire - now.tv_sec <= 0) {
				dprintf("timeout\n");
				process_timeout_event(s, now.tv_sec);
			}

			if (s->state != DEVST_ERROR) {
				fds[i].fd = s->dev->pkt_fd;
				fds[i].events = POLLRDNORM;
				i++;
			}

			if (timeout > s->expire - now.tv_sec)
				timeout = s->expire - now.tv_sec;
		}

		if (pending == 0 || (bringup_first && done))
			break;

		timeout_ms = timeout * 1000;

		for (x = 0; x < 2; x++) {
			int delta_ms;

			if (timeout_ms <= 0)
				timeout_ms = 100;

			nr = poll(fds, i, timeout_ms);
			prev = now;
			gettimeofday(&now, NULL);

			if ((nr > 0) && do_pkt_recv(nr, fds, now.tv_sec))
				break;

			if (loop_timeout >= 0 &&
			    now.tv_sec - start >= loop_timeout) {
				printf("IP-Config: no response after %d "
				       "secs - giving up\n", loop_timeout);
				rc = -1;
				goto bail;
			}

			delta_ms = (now.tv_sec - prev.tv_sec) * 1000;
			delta_ms += (now.tv_usec - prev.tv_usec) / 1000;

			dprintf("Delta: %d ms\n", delta_ms);

			timeout_ms -= delta_ms;
		}
	}
bail:
	if (fds)
		free(fds);
	return rc;
}

static int add_one_dev(struct netdev *dev)
{
	struct state *state;

	state = malloc(sizeof(struct state));
	if (!state)
		return -1;

	state->dev = dev;
	state->expire = time(NULL);
	state->retry_period = 1;

	/*
	 * Select the state that we start from.
	 */
	if (dev->caps & CAP_DHCP && dev->ip_addr == INADDR_ANY)
		state->restart_state = state->state = DEVST_DHCPDISC;
	else if (dev->caps & CAP_DHCP)
		state->restart_state = state->state = DEVST_DHCPREQ;
	else if (dev->caps & CAP_BOOTP)
		state->restart_state = state->state = DEVST_BOOTP;

	state->next = slist;
	slist = state;

	n_devices++;

	return 0;
}

static void parse_addr(uint32_t *addr, const char *ip)
{
	struct in_addr in;
	if (inet_aton(ip, &in) == 0) {
		fprintf(stderr, "%s: can't parse IP address '%s'\n",
			progname, ip);
		longjmp(abort_buf, 1);
	}
	*addr = in.s_addr;
}

static unsigned int parse_proto(const char *ip)
{
	unsigned int caps = 0;

	if (*ip == '\0' || strcmp(ip, "on") == 0 || strcmp(ip, "any") == 0)
		caps = CAP_BOOTP | CAP_DHCP | CAP_RARP;
	else if (strcmp(ip, "both") == 0)
		caps = CAP_BOOTP | CAP_RARP;
	else if (strcmp(ip, "dhcp") == 0)
		caps = CAP_BOOTP | CAP_DHCP;
	else if (strcmp(ip, "bootp") == 0)
		caps = CAP_BOOTP;
	else if (strcmp(ip, "rarp") == 0)
		caps = CAP_RARP;
	else if (strcmp(ip, "none") == 0 || strcmp(ip, "static") == 0
		 || strcmp(ip, "off") == 0)
		goto bail;
	else {
		fprintf(stderr, "%s: invalid protocol '%s'\n", progname, ip);
		longjmp(abort_buf, 1);
	}
bail:
	return caps;
}

static int add_all_devices(struct netdev *template);

static int parse_device(struct netdev *dev, char *ip)
{
	char *cp;
	int opt;
	int is_ip = 0;

	dprintf("IP-Config: parse_device: \"%s\"\n", ip);

	if (strncmp(ip, "ip=", 3) == 0) {
		ip += 3;
		is_ip = 1;
	} else if (strncmp(ip, "nfsaddrs=", 9) == 0) {
		ip += 9;
		is_ip = 1;	/* Not sure about this...? */
	}

	if (!strchr(ip, ':')) {
		/* Only one option, e.g. "ip=dhcp", or an interface name */
		if (is_ip) {
			dev->caps = parse_proto(ip);
			bringup_first = 1;
		} else {
			dev->name = ip;
		}
	} else {
		for (opt = 0; ip && *ip; ip = cp, opt++) {
			if ((cp = strchr(ip, ':'))) {
				*cp++ = '\0';
			}
			if (*ip == '\0')
				continue;
			dprintf("IP-Config: opt #%d: '%s'\n", opt, ip);
			switch (opt) {
			case 0:
				parse_addr(&dev->ip_addr, ip);
				dev->caps = 0;
				break;
			case 1:
				parse_addr(&dev->ip_server, ip);
				break;
			case 2:
				parse_addr(&dev->ip_gateway, ip);
				break;
			case 3:
				parse_addr(&dev->ip_netmask, ip);
				break;
			case 4:
				strncpy(dev->hostname, ip, SYS_NMLN - 1);
				dev->hostname[SYS_NMLN - 1] = '\0';
				memcpy(dev->reqhostname, dev->hostname,
				       SYS_NMLN);
				break;
			case 5:
				dev->name = ip;
				break;
			case 6:
				dev->caps = parse_proto(ip);
				break;
			case 7:
				parse_addr(&dev->ip_nameserver[0], ip);
				break;
			case 8:
				parse_addr(&dev->ip_nameserver[1], ip);
				break;
			case 9:
				/* NTP server - ignore */
				break;
			}
		}
	}

	if (dev->name == NULL ||
	    dev->name[0] == '\0' || strcmp(dev->name, "all") == 0) {
		add_all_devices(dev);
		bringup_first = 1;
		return 0;
	}
	return 1;
}

static void bringup_device(struct netdev *dev)
{
	if (netdev_up(dev) == 0) {
		if (dev->caps)
			add_one_dev(dev);
		else {
			dev->proto = PROTO_NONE;
			complete_device(dev);
		}
	}
}

static void bringup_one_dev(struct netdev *template, struct netdev *dev)
{
	if (template->ip_addr != INADDR_NONE)
		dev->ip_addr = template->ip_addr;
	if (template->ip_server != INADDR_NONE)
		dev->ip_server = template->ip_server;
	if (template->ip_gateway != INADDR_NONE)
		dev->ip_gateway = template->ip_gateway;
	if (template->ip_netmask != INADDR_NONE)
		dev->ip_netmask = template->ip_netmask;
	if (template->ip_nameserver[0] != INADDR_NONE)
		dev->ip_nameserver[0] = template->ip_nameserver[0];
	if (template->ip_nameserver[1] != INADDR_NONE)
		dev->ip_nameserver[1] = template->ip_nameserver[1];
	if (template->hostname[0] != '\0')
		strcpy(dev->hostname, template->hostname);
	if (template->reqhostname[0] != '\0')
		strcpy(dev->reqhostname, template->reqhostname);
	dev->caps &= template->caps;

	bringup_device(dev);
}

static struct netdev *add_device(char *info)
{
	struct netdev *dev;
	int i;

	dev = malloc(sizeof(struct netdev));
	if (dev == NULL) {
		fprintf(stderr, "%s: out of memory\n", progname);
		longjmp(abort_buf, 1);
	}

	memset(dev, 0, sizeof(struct netdev));
	dev->caps = default_caps;

	if (parse_device(dev, info) == 0)
		goto bail;

	if (netdev_init_if(dev) == -1)
		goto bail;

	if (bootp_init_if(dev) == -1)
		goto bail;

	if (packet_open(dev) == -1)
		goto bail;

	printf("IP-Config: %s hardware address", dev->name);
	for (i = 0; i < dev->hwlen; i++)
		printf("%c%02x", i == 0 ? ' ' : ':', dev->hwaddr[i]);
	printf(" mtu %d%s%s\n", dev->mtu,
	       dev->caps & CAP_DHCP ? " DHCP" :
	       dev->caps & CAP_BOOTP ? " BOOTP" : "",
	       dev->caps & CAP_RARP ? " RARP" : "");
	return dev;
bail:
	free(dev);
	return NULL;
}

static int add_all_devices(struct netdev *template)
{
	DIR *d;
	struct dirent *de;
	struct netdev *dev;
	char t[PATH_MAX], p[255];
	int i, fd;
	unsigned long flags;

	d = opendir(sysfs_class_net);
	if (!d)
		return 0;

	while ((de = readdir(d)) != NULL) {
		/* This excludes devices beginning with dots or "dummy",
		   as well as . or .. */
		if (de->d_name[0] == '.' || !strcmp(de->d_name, ".."))
			continue;
		i = snprintf(t, PATH_MAX - 1, "%s/%s/flags", sysfs_class_net,
			     de->d_name);
		if (i < 0 || i >= PATH_MAX - 1)
			continue;
		t[i] = '\0';
		fd = open(t, O_RDONLY);
		if (fd < 0) {
			perror(t);
			continue;
		}
		i = read(fd, &p, sizeof(p) - 1);
		close(fd);
		if (i < 0) {
			perror(t);
			continue;
		}
		p[i] = '\0';
		flags = strtoul(p, NULL, 0);
		/* Heuristic for if this is a reasonable boot interface.
		   This is the same
		   logic the in-kernel ipconfig uses... */
		if (!(flags & IFF_LOOPBACK) &&
		    (flags & (IFF_BROADCAST | IFF_POINTOPOINT))) {
			dprintf("Trying to bring up %s\n", de->d_name);

			dev = add_device(de->d_name);
			if (!dev)
				continue;
			bringup_one_dev(template, dev);
		}
	}
	closedir(d);
	return 1;
}

static int check_autoconfig(void)
{
	int ndev = 0, nauto = 0;
	struct state *s;

	for (s = slist; s; s = s->next) {
		ndev++;
		if (s->dev->caps)
			nauto++;
	}

	if (ndev == 0) {
		if (configured == 0) {
			fprintf(stderr, "%s: no devices to configure\n",
				progname);
			longjmp(abort_buf, 1);
		}
	}

	return nauto;
}

static void set_vendor_identifier(const char *id)
{
	int len = strlen(id);
	if (len >= 255) {
		fprintf(stderr,
			"%s: invalid vendor class identifier: "
			"%s\n", progname, id);
		longjmp(abort_buf, 1);
	}
	memcpy(vendor_class_identifier+2, id, len);
	vendor_class_identifier[0] = 60;
	vendor_class_identifier[1] = len;
	vendor_class_identifier_len = len+2;
}

int main(int argc, char *argv[])
    __attribute__ ((weak, alias("ipconfig_main")));

int ipconfig_main(int argc, char *argv[])
{
	struct netdev *dev;
	int c, port;
	int err = 0;

	/* If progname is set we're invoked from another program */
	if (!progname) {
		struct timeval now;
		progname = argv[0];
		gettimeofday(&now, NULL);
		srand48(now.tv_usec ^ (now.tv_sec << 24));
	}

	if ((err = setjmp(abort_buf)))
		return err;

	/* Default vendor identifier */
	set_vendor_identifier("Linux ipconfig");

	do {
		c = getopt(argc, argv, "c:d:i:onp:t:");
		if (c == EOF)
			break;

		switch (c) {
		case 'c':
			default_caps = parse_proto(optarg);
			break;
		case 'p':
			port = atoi(optarg);
			if (port <= 0 || port > USHRT_MAX) {
				fprintf(stderr,
					"%s: invalid port number %d\n",
					progname, port);
				longjmp(abort_buf, 1);
			}
			cfg_local_port = port;
			cfg_remote_port = cfg_local_port - 1;
			break;
		case 't':
			loop_timeout = atoi(optarg);
			if (loop_timeout < 0) {
				fprintf(stderr,
					"%s: invalid timeout %d\n",
					progname, loop_timeout);
				longjmp(abort_buf, 1);
			}
			break;
		case 'i':
			set_vendor_identifier(optarg);
			break;
		case 'o':
			bringup_first = 1;
			break;
		case 'n':
			do_not_config = 1;
			break;
		case 'd':
			dev = add_device(optarg);
			if (dev)
				bringup_device(dev);
			break;
		case '?':
			fprintf(stderr, "%s: invalid option -%c\n",
				progname, optopt);
			longjmp(abort_buf, 1);
		}
	} while (1);

	for (c = optind; c < argc; c++) {
		dev = add_device(argv[c]);
		if (dev)
			bringup_device(dev);
	}

	if (check_autoconfig()) {
		if (cfg_local_port != LOCAL_PORT) {
			printf("IP-Config: binding source port to %d, "
			       "dest to %d\n",
			       cfg_local_port, cfg_remote_port);
		}
		err = loop();
	}

	return err;
}
