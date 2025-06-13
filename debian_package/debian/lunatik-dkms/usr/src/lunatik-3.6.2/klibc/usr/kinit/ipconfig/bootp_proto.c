/*
 * BOOTP packet protocol handling.
 */
#include <sys/types.h>
#include <sys/uio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <netinet/in.h>

#include "ipconfig.h"
#include "netdev.h"
#include "bootp_packet.h"
#include "bootp_proto.h"
#include "packet.h"

static uint8_t bootp_options[312] = {
	[  0] = 99, 130, 83, 99,/* RFC1048 magic cookie */
	[  4] = 1, 4,		/*   4-  9 subnet mask */
	[ 10] = 3, 4,		/*  10- 15 default gateway */
	[ 16] = 5, 8,		/*  16- 25 nameserver */
	[ 26] = 12, 32,		/*  26- 59 host name */
	[ 60] = 40, 32,		/*  60- 95 nis domain name */
	[ 96] = 17, 40,		/*  96-137 boot path */
	[138] = 57, 2, 1, 150,	/* 138-141 extension buffer */
	[142] = 255,		/* end of list */
};

/*
 * Send a plain bootp request packet with options
 */
int bootp_send_request(struct netdev *dev)
{
	struct bootp_hdr bootp;
	struct iovec iov[] = {
		/* [0] = ip + udp headers */
		[1] = {&bootp, sizeof(bootp)},
		[2] = {bootp_options, 312}
	};

	memset(&bootp, 0, sizeof(struct bootp_hdr));

	bootp.op	= BOOTP_REQUEST, bootp.htype = dev->hwtype;
	bootp.hlen	= dev->hwlen;
	bootp.xid	= dev->bootp.xid;
	bootp.ciaddr	= dev->ip_addr;
	bootp.secs	= htons(time(NULL) - dev->open_time);
	memcpy(bootp.chaddr, dev->hwaddr, 16);

	dprintf("-> bootp xid 0x%08x secs 0x%08x ",
		bootp.xid, ntohs(bootp.secs));

	return packet_send(dev, iov, 2);
}

/*
 * DESCRIPTION
 *  bootp_ext119_decode() decodes Domain Search Option data.
 *  The decoded string is separated with ' '.
 *  For example, it is either "foo.bar.baz. bar.baz.", "foo.bar.", or "foo.".
 *
 * ARGUMENTS
 *  const uint8_t *ext
 *   *ext is a pointer to a DHCP Domain Search Option data. *ext does not
 *   include a tag(code) octet and a length octet in DHCP options.
 *   For example, if *ext is {3, 'f', 'o', 'o', 0}, this function returns
 *   a pointer to a "foo." string.
 *
 *  int16_t ext_size
 *   ext_size is the memory size of *ext. For example,
 *   if *ext is {3, 'f', 'o', 'o', 0}, ext_size must be 5.
 *
 *  uint8_t *tmp
 *   *tmp is a pointer to a temporary memory space for decoding.
 *   The memory size must be equal to or more than ext_size.
 *   'memset(tmp, 0, sizeof(tmp));' is not required, but values in *tmp
 *   are changed in decoding process.
 *
 * RETURN VALUE
 *  if OK, a pointer to a decoded string malloc-ed
 *  else , NULL
 *
 * SEE ALSO RFC3397
 */
static char *bootp_ext119_decode(const void *ext, int16_t ext_size, void *tmp)
{
	uint8_t *u8ext;
	int_fast32_t i;
	int_fast32_t decoded_size;
	int_fast8_t currentdomain_is_singledot;

	/* only for validating *ext */
	uint8_t *is_pointee;
	int_fast32_t is_pointee_size;

	/* only for structing a decoded string */
	char *decoded_str;
	int_fast32_t dst_i;

	if (ext == NULL || ext_size <= 0 || tmp == NULL)
		return NULL;

	u8ext = (uint8_t *)ext;
	is_pointee = tmp;
	memset(is_pointee, 0, (size_t)ext_size);
	is_pointee_size = 0;

	/*
	 * validate the format of *ext and
	 * calculate the memory size for a decoded string
	 */
	i = 0;
	decoded_size = 0;
	currentdomain_is_singledot = 1;
	while (1) {
		if (i >= ext_size)
			return NULL;

		if (u8ext[i] == 0) {
			/* Zero-ending */
			if (currentdomain_is_singledot)
				decoded_size++; /* for '.' */
			decoded_size++; /* for ' ' or '\0' */
			currentdomain_is_singledot = 1;
			i++;
			if (i == ext_size)
				break;
			is_pointee_size = i;
		} else if (u8ext[i] < 0x40) {
			/* Label(sub-domain string) */
			int j;

			/* loosely validate characters for domain names */
			if (i + u8ext[i] >= ext_size)
				return NULL;
			for (j = i + 1; j <= i + u8ext[i]; j++)
				if (!(u8ext[j] == '-' ||
				     ('0' <= u8ext[j] && u8ext[j] <= '9') ||
				     ('A' <= u8ext[j] && u8ext[j] <= 'Z') ||
				     ('a' <= u8ext[j] && u8ext[j] <= 'z')))
					return NULL;

			is_pointee[i] = 1;
			decoded_size += u8ext[i] + 1; /* for Label + '.' */
			currentdomain_is_singledot = 0;
			i += u8ext[i] + 1;
		} else if (u8ext[i] < 0xc0)
			return NULL;

		else {
			/* Compression-pointer (to a prior Label) */
			int_fast32_t p;

			if (i + 1 >= ext_size)
				return NULL;

			p = ((0x3f & u8ext[i]) << 8) + u8ext[i + 1];
			if (!(p < is_pointee_size && is_pointee[p]))
				return NULL;

			while (1) {
				/* u8ext[p] was validated */
				if (u8ext[p] == 0) {
					/* Zero-ending */
					decoded_size++;
					break;
				} else if (u8ext[p] < 0x40) {
					/* Label(sub-domain string) */
					decoded_size += u8ext[p] + 1;
					p += u8ext[p] + 1;
				} else {
					/* Compression-pointer */
					p = ((0x3f & u8ext[p]) << 8)
						+ u8ext[p + 1];
				}
			}

			currentdomain_is_singledot = 1;
			i += 2;
			if (i == ext_size)
				break;
			is_pointee_size = i;
		}
	}


	/*
	 * construct a decoded string
	 */
	decoded_str = malloc(decoded_size);
	if (decoded_str == NULL)
		return NULL;

	i = 0;
	dst_i = 0;
	currentdomain_is_singledot = 1;
	while (1) {
		if (u8ext[i] == 0) {
			/* Zero-ending */
			if (currentdomain_is_singledot) {
				if (dst_i != 0)
					dst_i++;
				decoded_str[dst_i] = '.';
			}
			dst_i++;
			decoded_str[dst_i] = ' ';

			currentdomain_is_singledot = 1;
			i++;
			if (i == ext_size)
				break;
		} else if (u8ext[i] < 0x40) {
			/* Label(sub-domain string) */
			if (dst_i != 0)
				dst_i++;
			memcpy(&decoded_str[dst_i], &u8ext[i + 1],
			       (size_t)u8ext[i]);
			dst_i += u8ext[i];
			decoded_str[dst_i] = '.';

			currentdomain_is_singledot = 0;
			i += u8ext[i] + 1;
		} else {
			/* Compression-pointer (to a prior Label) */
			int_fast32_t p;

			p = ((0x3f & u8ext[i]) << 8) + u8ext[i + 1];
			while (1) {
				if (u8ext[p] == 0) {
					/* Zero-ending */
					decoded_str[dst_i++] = '.';
					decoded_str[dst_i] = ' ';
					break;
				} else if (u8ext[p] < 0x40) {
					/* Label(sub-domain string) */
					dst_i++;
					memcpy(&decoded_str[dst_i],
					       &u8ext[p + 1],
					       (size_t)u8ext[p]);
					dst_i += u8ext[p];
					decoded_str[dst_i] = '.';

					p += u8ext[p] + 1;
				} else {
					/* Compression-pointer */
					p = ((0x3f & u8ext[p]) << 8)
						+ u8ext[p + 1];
				}
			}

			currentdomain_is_singledot = 1;
			i += 2;
			if (i == ext_size)
				break;
		}
	}
	decoded_str[dst_i] = '\0';
#ifdef DEBUG
	if (dst_i + 1 != decoded_size) {
		dprintf("bug:%s():bottom: malloc(%ld), write(%ld)\n",
			__func__, (long)decoded_size, (long)(dst_i + 1));
		exit(1);
	}
#endif
	return decoded_str;
}

/*
 * DESCRIPTION
 *  bootp_ext121_decode() decodes Classless Route Option data.
 *
 * ARGUMENTS
 *  const uint8_t *ext
 *   *ext is a pointer to a DHCP Classless Route Option data.
 *   For example, if *ext is {16, 192, 168, 192, 168, 42, 1},
 *   this function returns a pointer to
 *   {
 *     subnet = 192.168.0.0;
 *     netmask_width = 16;
 *     gateway = 192.168.42.1;
 *     next = NULL;
 *   }
 *
 *  int16_t ext_size
 *   ext_size is the memory size of *ext. For example,
 *   if *ext is {16, 192, 168, 192, 168, 42, 1}, ext_size must be 7.
 *
 * RETURN VALUE
 *  if OK, a pointer to a decoded struct route malloc-ed
 *  else , NULL
 *
 * SEE ALSO RFC3442
 */
struct route *bootp_ext121_decode(const uint8_t *ext, int16_t ext_size)
{
	int16_t index = 0;
	uint8_t netmask_width;
	uint8_t significant_octets;
	struct route *routes = NULL;
	struct route *prev_route = NULL;

	while (index < ext_size) {
		netmask_width = ext[index];
		index++;
		if (netmask_width > 32) {
			printf("IP-Config: Given Classless Route Option subnet mask width '%u' "
		            "exceeds IPv4 limit of 32. Ignoring remaining option.\n",
			        netmask_width);
			return routes;
		}
		significant_octets = netmask_width / 8 + (netmask_width % 8 > 0);
		if (ext_size - index < significant_octets + 4) {
			printf("IP-Config: Given Classless Route Option remaining lengths (%u octets) "
			        "is shorter than the expected %u octets. Ignoring remaining options.\n",
			        ext_size - index, significant_octets + 4);
			return routes;
		}

		struct route *route = malloc(sizeof(struct route));
		if (route == NULL)
			return routes;

		/* convert only significant octets from byte array into integer in network byte order */
		route->subnet = 0;
		memcpy(&route->subnet, &ext[index], significant_octets);
		index += significant_octets;
		/* RFC3442 demands: After deriving a subnet number and subnet mask from
		   each destination descriptor, the DHCP client MUST zero any bits in
		   the subnet number where the corresponding bit in the mask is zero. */
		route->subnet &= netdev_genmask(netmask_width);

		/* convert octet array into network byte order */
		memcpy(&route->gateway, &ext[index], 4);
		index += 4;

		route->netmask_width = netmask_width;
		route->next = NULL;

		if (prev_route == NULL) {
			routes = route;
		} else {
			prev_route->next = route;
		}
		prev_route = route;
	}
	return routes;
}

/*
 * Parse a bootp reply packet
 */
int bootp_parse(struct netdev *dev, struct bootp_hdr *hdr,
		uint8_t *exts, int extlen)
{
	uint8_t ext119_buf[BOOTP_EXTS_SIZE];
	int16_t ext119_len = 0;
	uint8_t ext121_buf[BOOTP_EXTS_SIZE];
	int16_t ext121_len = 0;

	dev->bootp.gateway	= hdr->giaddr;
	dev->ip_addr		= hdr->yiaddr;
	dev->ip_server		= hdr->siaddr;
	dev->ip_netmask		= INADDR_ANY;
	dev->ip_broadcast	= INADDR_ANY;
	dev->ip_gateway		= hdr->giaddr;
	dev->ip_nameserver[0]	= INADDR_ANY;
	dev->ip_nameserver[1]	= INADDR_ANY;
	dev->hostname[0]	= '\0';
	dev->nisdomainname[0]	= '\0';
	dev->bootpath[0]	= '\0';
	memcpy(&dev->filename, &hdr->boot_file, FNLEN);

	if (extlen >= 4 && exts[0] == 99 && exts[1] == 130 &&
	    exts[2] == 83 && exts[3] == 99) {
		uint8_t *ext;

		for (ext = exts + 4; ext - exts < extlen;) {
			int len;
			uint8_t opt = *ext++;

			if (opt == 0)
				continue;
			else if (opt == 255)
				break;

			if (ext - exts >= extlen)
				break;
			len = *ext++;

			if (ext - exts + len > extlen)
				break;
			switch (opt) {
			case 1:	/* subnet mask */
				if (len == 4)
					memcpy(&dev->ip_netmask, ext, 4);
				break;
			case 3:	/* default gateway */
				if (len >= 4)
					memcpy(&dev->ip_gateway, ext, 4);
				break;
			case 6:	/* DNS server */
				if (len >= 4)
					memcpy(&dev->ip_nameserver, ext,
					       len >= 8 ? 8 : 4);
				break;
			case 12:	/* host name */
				if (len > sizeof(dev->hostname) - 1)
					len = sizeof(dev->hostname) - 1;
				memcpy(&dev->hostname, ext, len);
				dev->hostname[len] = '\0';
				break;
			case 15:	/* domain name */
				if (len > sizeof(dev->dnsdomainname) - 1)
					len = sizeof(dev->dnsdomainname) - 1;
				memcpy(&dev->dnsdomainname, ext, len);
				dev->dnsdomainname[len] = '\0';
				break;
			case 17:	/* root path */
				if (len > sizeof(dev->bootpath) - 1)
					len = sizeof(dev->bootpath) - 1;
				memcpy(&dev->bootpath, ext, len);
				dev->bootpath[len] = '\0';
				break;
			case 26:	/* interface MTU */
				if (len == 2)
					dev->mtu = (ext[0] << 8) + ext[1];
				break;
			case 28:	/* broadcast addr */
				if (len == 4)
					memcpy(&dev->ip_broadcast, ext, 4);
				break;
			case 40:	/* NIS domain name */
				if (len > sizeof(dev->nisdomainname) - 1)
					len = sizeof(dev->nisdomainname) - 1;
				memcpy(&dev->nisdomainname, ext, len);
				dev->nisdomainname[len] = '\0';
				break;
			case 54:	/* server identifier */
				if (len == 4 && !dev->ip_server)
					memcpy(&dev->ip_server, ext, 4);
				break;
			case 119:	/* Domain Search Option */
				if (ext119_len >= 0 &&
				    ext119_len + len <= sizeof(ext119_buf)) {
					memcpy(ext119_buf + ext119_len,
					       ext, len);
					ext119_len += len;
				} else
					ext119_len = -1;

				break;
			case 121:	/* Classless Static Route Option (RFC3442) */
				if (ext121_len >= 0 &&
				    ext121_len + len <= sizeof(ext121_buf)) {
					memcpy(ext121_buf + ext121_len,
					       ext, len);
					ext121_len += len;
				} else
					ext121_len = -1;

				break;
			}

			ext += len;
		}
	}
	if (ext119_len > 0) {
		char *ret;
		uint8_t ext119_tmp[BOOTP_EXTS_SIZE];

		ret = bootp_ext119_decode(ext119_buf, ext119_len, ext119_tmp);
		if (ret != NULL) {
			if (dev->domainsearch != NULL)
				free(dev->domainsearch);
			dev->domainsearch = ret;
		}
	}

	if (ext121_len > 0) {
		struct route *ret;

		ret = bootp_ext121_decode(ext121_buf, ext121_len);
		if (ret != NULL) {
			struct route *cur = dev->routes;
			struct route *next;
			while (cur != NULL) {
				next = cur->next;
				free(cur);
				cur = next;
			}
			dev->routes = ret;
		}
	}

	/*
	 * Got packet.
	 */
	return 1;
}

/*
 * Receive a bootp reply and parse packet
 * Returns:
 *-1 = Error in packet_recv, try again later
 * 0 = Unexpected packet, discarded
 * 1 = Correctly received and parsed packet
 */
int bootp_recv_reply(struct netdev *dev)
{
	struct bootp_hdr bootp;
	uint8_t bootp_options[BOOTP_EXTS_SIZE];
	struct iovec iov[] = {
		/* [0] = ip + udp headers */
		[1] = {&bootp, sizeof(struct bootp_hdr)},
		[2] = {bootp_options, sizeof(bootp_options)}
	};
	int ret;

	ret = packet_recv(dev, iov, 3);
	if (ret <= 0)
		return ret;

	if (ret < sizeof(struct bootp_hdr) ||
	    bootp.op != BOOTP_REPLY ||	/* RFC951 7.5 */
	    bootp.xid != dev->bootp.xid ||
	    memcmp(bootp.chaddr, dev->hwaddr, 16))
		return 0;

	ret -= sizeof(struct bootp_hdr);

	return bootp_parse(dev, &bootp, bootp_options, ret);
}

/*
 * Initialise interface for bootp.
 */
int bootp_init_if(struct netdev *dev)
{
	short flags;

	/*
	 * Get the device flags
	 */
	if (netdev_getflags(dev, &flags))
		return -1;

	/*
	 * We can't do DHCP nor BOOTP if this device
	 * doesn't support broadcast.
	 */
	if (dev->mtu < 364 || (flags & IFF_BROADCAST) == 0) {
		dev->caps &= ~(CAP_BOOTP | CAP_DHCP);
		return 0;
	}

	/*
	 * Get a random XID
	 */
	dev->bootp.xid = (uint32_t) lrand48();
	dev->open_time = time(NULL);

	return 0;
}
