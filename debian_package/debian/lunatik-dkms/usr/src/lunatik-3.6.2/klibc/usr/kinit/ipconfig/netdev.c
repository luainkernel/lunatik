/*
 * ioctl-based device configuration
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <netinet/in.h>
#include <linux/route.h>
#include <linux/sockios.h>

#include "netdev.h"

static int cfd = -1;

static void copy_name(struct netdev *dev, struct ifreq *ifr)
{
	strncpy(ifr->ifr_name, dev->name, sizeof(ifr->ifr_name));
	ifr->ifr_name[sizeof(ifr->ifr_name) - 1] = '\0';
}

int netdev_getflags(struct netdev *dev, short *flags)
{
	struct ifreq ifr;

	copy_name(dev, &ifr);

	if (ioctl(cfd, SIOCGIFFLAGS, &ifr) == -1) {
		perror("SIOCGIFFLAGS");
		return -1;
	}

	*flags = ifr.ifr_flags;
	return 0;
}

static int netdev_sif_addr(struct ifreq *ifr, int cmd, uint32_t addr)
{
	struct sockaddr_in sin;

	memset(&sin, 0, sizeof(sin));
	sin.sin_family = AF_INET;
	sin.sin_addr.s_addr = addr;

	memcpy(&ifr->ifr_addr, &sin, sizeof sin);

	return ioctl(cfd, cmd, ifr);
}

int netdev_setaddress(struct netdev *dev)
{
	struct ifreq ifr;

	copy_name(dev, &ifr);

	if (dev->ip_addr != INADDR_ANY &&
	    netdev_sif_addr(&ifr, SIOCSIFADDR, dev->ip_addr) == -1) {
		perror("SIOCSIFADDR");
		return -1;
	}

	if (dev->ip_broadcast != INADDR_ANY &&
	    netdev_sif_addr(&ifr, SIOCSIFBRDADDR, dev->ip_broadcast) == -1) {
		perror("SIOCSIFBRDADDR");
		return -1;
	}

	if (dev->ip_netmask != INADDR_ANY &&
	    netdev_sif_addr(&ifr, SIOCSIFNETMASK, dev->ip_netmask) == -1) {
		perror("SIOCSIFNETMASK");
		return -1;
	}

	return 0;
}

static void set_s_addr(struct sockaddr *saddr, uint32_t ipaddr)
{
	struct sockaddr_in sin = {
		.sin_family = AF_INET,
		.sin_addr.s_addr = ipaddr,
	};
	memcpy(saddr, &sin, sizeof sin);
}

int netdev_setroutes(struct netdev *dev)
{
	struct rtentry r;

	/* RFC3442 demands:
	   If the DHCP server returns both a Classless Static Routes option and
	   a Router option, the DHCP client MUST ignore the Router option. */
	if (dev->routes != NULL) {
		struct route *cur;
		for (cur = dev->routes; cur != NULL; cur = cur->next) {
			memset(&r, 0, sizeof(r));

			r.rt_dev = dev->name;
			set_s_addr(&r.rt_dst, cur->subnet);
			set_s_addr(&r.rt_gateway, cur->gateway);
			set_s_addr(&r.rt_genmask, netdev_genmask(cur->netmask_width));
			r.rt_flags = RTF_UP;
			if (cur->gateway != 0) {
				r.rt_flags |= RTF_GATEWAY;
			}

			if (ioctl(cfd, SIOCADDRT, &r) == -1 && errno != EEXIST) {
				perror("SIOCADDRT");
				return -1;
			}
		}
	} else if (dev->ip_gateway != INADDR_ANY) {
		memset(&r, 0, sizeof(r));

		set_s_addr(&r.rt_dst, INADDR_ANY);
		set_s_addr(&r.rt_gateway, dev->ip_gateway);
		set_s_addr(&r.rt_genmask, INADDR_ANY);
		r.rt_flags = RTF_UP | RTF_GATEWAY;

		if (ioctl(cfd, SIOCADDRT, &r) == -1 && errno != EEXIST) {
			perror("SIOCADDRT");
			return -1;
		}
	}
	return 0;
}

int netdev_setmtu(struct netdev *dev)
{
	struct ifreq ifr;

	copy_name(dev, &ifr);
	ifr.ifr_mtu = dev->mtu;

	return ioctl(cfd, SIOCSIFMTU, &ifr);
}

static int netdev_gif_addr(struct ifreq *ifr, int cmd, uint32_t * ptr)
{
	struct sockaddr_in *sin = (struct sockaddr_in *)&ifr->ifr_addr;

	if (ioctl(cfd, cmd, ifr) == -1)
		return -1;

	*ptr = sin->sin_addr.s_addr;

	return 0;
}

int netdev_up(struct netdev *dev)
{
	struct ifreq ifr;

	copy_name(dev, &ifr);

	if (ioctl(cfd, SIOCGIFFLAGS, &ifr) == -1) {
		perror("SIOCGIFFLAGS");
		return -1;
	}

	ifr.ifr_flags |= IFF_UP;

	if (ioctl(cfd, SIOCSIFFLAGS, &ifr) == -1) {
		perror("SIOCSIFFLAGS");
		return -1;
	}
	return 0;
}

int netdev_down(struct netdev *dev)
{
	struct ifreq ifr;

	copy_name(dev, &ifr);

	if (ioctl(cfd, SIOCGIFFLAGS, &ifr) == -1) {
		perror("SIOCGIFFLAGS");
		return -1;
	}

	ifr.ifr_flags &= ~IFF_UP;

	if (ioctl(cfd, SIOCSIFFLAGS, &ifr) == -1) {
		perror("SIOCSIFFLAGS");
		return -1;
	}
	return 0;
}

int netdev_init_if(struct netdev *dev)
{
	struct ifreq ifr;

	if (cfd == -1)
		cfd = socket(AF_INET, SOCK_DGRAM, 0);
	if (cfd == -1) {
		fprintf(stderr, "ipconfig: %s: socket(AF_INET): %s\n",
			dev->name, strerror(errno));
		return -1;
	}

	copy_name(dev, &ifr);

	if (ioctl(cfd, SIOCGIFINDEX, &ifr) == -1) {
		fprintf(stderr, "ipconfig: %s: SIOCGIFINDEX: %s\n",
			dev->name, strerror(errno));
		return -1;
	}

	dev->ifindex = ifr.ifr_ifindex;

	if (ioctl(cfd, SIOCGIFMTU, &ifr) == -1) {
		fprintf(stderr, "ipconfig: %s: SIOCGIFMTU: %s\n",
			dev->name, strerror(errno));
		return -1;
	}

	dev->mtu = ifr.ifr_mtu;

	if (ioctl(cfd, SIOCGIFHWADDR, &ifr) == -1) {
		fprintf(stderr, "ipconfig: %s: SIOCGIFHWADDR: %s\n",
			dev->name, strerror(errno));
		return -1;
	}

	dev->hwtype = ifr.ifr_hwaddr.sa_family;
	dev->hwlen  = 0;

	switch (dev->hwtype) {
	case ARPHRD_ETHER:
		dev->hwlen = 6;
		break;
	case ARPHRD_EUI64:
		dev->hwlen = 8;
		break;
	case ARPHRD_LOOPBACK:
		dev->hwlen = 0;
		break;
	default:
		return -1;
	}

	memcpy(dev->hwaddr, ifr.ifr_hwaddr.sa_data, dev->hwlen);
	memset(dev->hwbrd, 0xff, dev->hwlen);

	/*
	 * Try to get the current interface information.
	 */
	if (dev->ip_addr == INADDR_NONE &&
	    netdev_gif_addr(&ifr, SIOCGIFADDR, &dev->ip_addr) == -1) {
		fprintf(stderr, "ipconfig: %s: SIOCGIFADDR: %s\n",
			dev->name, strerror(errno));
		dev->ip_addr = 0;
		dev->ip_broadcast = 0;
		dev->ip_netmask = 0;
		return 0;
	}

	if (dev->ip_broadcast == INADDR_NONE &&
	    netdev_gif_addr(&ifr, SIOCGIFBRDADDR, &dev->ip_broadcast) == -1) {
		fprintf(stderr, "ipconfig: %s: SIOCGIFBRDADDR: %s\n",
			dev->name, strerror(errno));
		dev->ip_broadcast = 0;
	}

	if (dev->ip_netmask == INADDR_NONE &&
	    netdev_gif_addr(&ifr, SIOCGIFNETMASK, &dev->ip_netmask) == -1) {
		fprintf(stderr, "ipconfig: %s: SIOCGIFNETMASK: %s\n",
			dev->name, strerror(errno));
		dev->ip_netmask = 0;
	}

	return 0;
}
