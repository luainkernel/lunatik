#ifndef IPCONFIG_NETDEV_H
#define IPCONFIG_NETDEV_H

#include <arpa/inet.h>
#include <sys/utsname.h>
#include <net/if.h>

#define BPLEN		256
#define FNLEN		128			/* from DHCP  RFC 2131 */

struct route {
	uint32_t subnet;			/* subnet            */
	uint32_t netmask_width;	/* subnet mask width */
	uint32_t gateway;		/* gateway           */
	struct route *next;
};

struct netdev {
	char *name;		/* Device name          */
	unsigned int ifindex;	/* interface index      */
	unsigned int hwtype;	/* ARPHRD_xxx           */
	unsigned int hwlen;	/* HW address length    */
	uint8_t hwaddr[16];	/* HW address           */
	uint8_t hwbrd[16];	/* Broadcast HW address */
	unsigned int mtu;	/* Device mtu           */
	unsigned int caps;	/* Capabilities         */
	time_t open_time;

	struct {		/* BOOTP/DHCP info      */
		int fd;
		uint32_t xid;
		uint32_t gateway; /* BOOTP/DHCP gateway   */
	} bootp;

	struct {		/* RARP information     */
		int fd;
	} rarp;

	uint8_t proto;          /* a protocol used (e.g. PROTO_DHCP) */
	uint32_t ip_addr;	/* my address           */
	uint32_t ip_broadcast;	/* broadcast address    */
	uint32_t ip_server;	/* server address       */
	uint32_t ip_netmask;	/* my subnet mask       */
	uint32_t ip_gateway;	/* my gateway           */
	uint32_t ip_nameserver[2];	/* two nameservers      */
	uint32_t serverid;		/* dhcp serverid        */
	uint32_t dhcpleasetime;	/* duration in seconds  */
	char reqhostname[SYS_NMLN];	/* requested hostname   */
	char hostname[SYS_NMLN];	/* hostname             */
	char dnsdomainname[SYS_NMLN];	/* dns domain name      */
	char nisdomainname[SYS_NMLN];	/* nis domain name      */
	char bootpath[BPLEN];	/* boot path            */
	char filename[FNLEN];   /* filename             */
	char *domainsearch;	/* decoded, NULL or malloc-ed  */
	struct route *routes;	/* decoded, NULL or malloc-ed list */
	long uptime;		/* when complete configuration */
	int pkt_fd;		/* packet socket for this interface */
	struct netdev *next;	/* next configured i/f  */
};

extern struct netdev *ifaces;

/*
 * Device capabilities
 */
#define CAP_BOOTP	(1<<0)
#define CAP_DHCP	(1<<1)
#define CAP_RARP	(1<<2)

/*
 * Device states
 */
#define DEVST_UP	0
#define DEVST_BOOTP	1
#define DEVST_DHCPDISC	2
#define DEVST_DHCPREQ	3
#define DEVST_COMPLETE	4
#define DEVST_ERROR	5

int netdev_getflags(struct netdev *dev, short *flags);
int netdev_setaddress(struct netdev *dev);
int netdev_setroutes(struct netdev *dev);
int netdev_up(struct netdev *dev);
int netdev_down(struct netdev *dev);
int netdev_init_if(struct netdev *dev);
int netdev_setmtu(struct netdev *dev);

static inline int netdev_running(struct netdev *dev)
{
	short flags;
	int ret = netdev_getflags(dev, &flags);

	return ret ? 0 : !!(flags & IFF_RUNNING);
}

static inline uint32_t netdev_genmask(uint32_t netmask_width)
{
	/* Map netmask width to network mask in network byte order.
	   Example: 24 -> "255.255.255.0" -> htonl(0xFFFFFF00) */
	if (netmask_width == 0) {
		return 0;
	} else {
		return htonl(~((1u << (32 - netmask_width)) - 1));
	}
}

#endif /* IPCONFIG_NETDEV_H */
