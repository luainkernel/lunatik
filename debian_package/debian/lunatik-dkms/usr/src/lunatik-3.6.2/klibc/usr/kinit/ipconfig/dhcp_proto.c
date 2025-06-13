/*
 * DHCP RFC 2131 and 2132
 */
#include <sys/types.h>
#include <sys/uio.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "ipconfig.h"
#include "netdev.h"
#include "bootp_packet.h"
#include "bootp_proto.h"
#include "dhcp_proto.h"
#include "packet.h"

static uint8_t dhcp_params[] = {
	1,			/* subnet mask */
	3,			/* default gateway */
	6,			/* DNS server */
	12,			/* host name */
	15,			/* domain name */
	17,			/* root path */
	26,			/* interface mtu */
	28,			/* broadcast addr */
	40,			/* NIS domain name (why?) */
	119,			/* Domain Search Option */
	121,			/* Classless Static Route Option (RFC3442) */
};

static uint8_t dhcp_discover_hdr[] = {
	99, 130, 83, 99,		/* bootp cookie */
	53, 1, DHCPDISCOVER,		/* dhcp message type */
	55, sizeof(dhcp_params),	/* parameter list */
};

static uint8_t dhcp_request_hdr[] = {
	99, 130, 83, 99,		/* boot cookie */
	53, 1, DHCPREQUEST,		/* dhcp message type */
#define SERVER_IP_OFF 9
	54, 4, 0, 0, 0, 0,		/* server IP */
#define REQ_IP_OFF 15
	50, 4, 0, 0, 0, 0,		/* requested IP address */
	55, sizeof(dhcp_params),	/* parameter list */
};

static uint8_t dhcp_end[] = {
	255,
};

/* Both iovecs below have to have the same structure, since dhcp_send()
   pokes at the internals */
#define DHCP_IOV_LEN 8

static struct iovec dhcp_discover_iov[DHCP_IOV_LEN] = {
	/* [0] = ip + udp header */
	/* [1] = bootp header */
	[2] = {dhcp_discover_hdr, sizeof(dhcp_discover_hdr)},
	[3] = {dhcp_params, sizeof(dhcp_params)},
	/* [4] = optional vendor class */
	/* [5] = optional hostname */
	/* [6] = {dhcp_end, sizeof(dhcp_end)} */
	/* [7] = optional padding */
};

static struct iovec dhcp_request_iov[DHCP_IOV_LEN] = {
	/* [0] = ip + udp header */
	/* [1] = bootp header */
	[2] = {dhcp_request_hdr, sizeof(dhcp_request_hdr)},
	[3] = {dhcp_params, sizeof(dhcp_params)},
	/* [4] = optional vendor class */
	/* [5] = optional hostname */
	/* [6] = {dhcp_end, sizeof(dhcp_end)} */
	/* [7] = optional padding */
};

/*
 * Parse a DHCP response packet
 * Returns:
 * 0 = Unexpected packet, not parsed
 * 2 = DHCPOFFER (from dhcp_proto.h)
 * 5 = DHCPACK
 * 6 = DHCPNACK
 */
static int dhcp_parse(struct netdev *dev, struct bootp_hdr *hdr,
		      uint8_t *exts, int extlen)
{
	uint8_t type = 0;
	uint32_t serverid = INADDR_NONE;
	uint32_t leasetime = 0;
	int ret = 0;

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
			case 51:	/* IP Address Lease Time */
				if (len == 4)
					leasetime = ntohl(*(uint32_t *)ext);
				break;
			case 53:	/* DHCP Message Type */
				if (len == 1)
					type = *ext;
				break;
			case 54:	/* Server Identifier */
				if (len == 4)
					memcpy(&serverid, ext, 4);
				break;
			}
			ext += len;
		}
	}

	switch (type) {
	case DHCPOFFER:
		ret = bootp_parse(dev, hdr, exts, extlen) ? DHCPOFFER : 0;
		if (ret == DHCPOFFER && serverid != INADDR_NONE)
			dev->serverid = serverid;
		dprintf("\n   dhcp offer\n");
		break;

	case DHCPACK:
		dev->dhcpleasetime = leasetime;
		ret = bootp_parse(dev, hdr, exts, extlen) ? DHCPACK : 0;
		dprintf("\n   dhcp ack\n");
		break;

	case DHCPNAK:
		ret = DHCPNAK;
		dprintf("\n   dhcp nak\n");
		break;
	}
	return ret;
}

/*
 * Receive and parse a DHCP packet
 * Returns:
 *-1 = Error in packet_recv, try again later
 * 0 = Unexpected packet, discarded
 * 2 = DHCPOFFER (from dhcp_proto.h)
 * 5 = DHCPACK
 * 6 = DHCPNACK
 */
static int dhcp_recv(struct netdev *dev)
{
	struct bootp_hdr bootp;
	uint8_t dhcp_options[BOOTP_EXTS_SIZE];
	struct iovec iov[] = {
		/* [0] = ip + udp header */
		[1] = {&bootp, sizeof(struct bootp_hdr)},
		[2] = {dhcp_options, sizeof(dhcp_options)}
	};
	int ret;

	ret = packet_recv(dev, iov, 3);
	if (ret <= 0)
		return ret;

	dprintf("\n   dhcp xid %08x ", dev->bootp.xid);

	if (ret < sizeof(struct bootp_hdr) || bootp.op != BOOTP_REPLY ||
	    /* RFC951 7.5 */ bootp.xid != dev->bootp.xid ||
	    memcmp(bootp.chaddr, dev->hwaddr, 16))
		return 0;

	ret -= sizeof(struct bootp_hdr);

	return dhcp_parse(dev, &bootp, dhcp_options, ret);
}

static int dhcp_send(struct netdev *dev, struct iovec *vec)
{
	struct bootp_hdr bootp;
	char dhcp_hostname[SYS_NMLN+2];
	uint8_t padding[BOOTP_MIN_LEN - sizeof(struct bootp_hdr)];
	int padding_len;
	int i = 4;
	int j;

	memset(&bootp, 0, sizeof(struct bootp_hdr));

	bootp.op	= BOOTP_REQUEST;
	bootp.htype	= dev->hwtype;
	bootp.hlen	= dev->hwlen;
	bootp.xid	= dev->bootp.xid;
	bootp.ciaddr	= INADDR_ANY;
	/* yiaddr should always be set to 0 for the messages we're likely
	 * to send as a DHCP client: DHCPDISCOVER, DHCPREQUEST, DHCPDECLINE,
	 * DHCPINFORM, DHCPRELEASE
	 * cf. RFC2131 section 4.1.1, table 5.
	 */
	bootp.yiaddr	= INADDR_ANY;
	bootp.giaddr	= INADDR_ANY;
	bootp.flags	= htons(0x8000);
	bootp.secs	= htons(time(NULL) - dev->open_time);
	memcpy(bootp.chaddr, dev->hwaddr, 16);

	vec[1].iov_base	= &bootp;
	vec[1].iov_len	= sizeof(struct bootp_hdr);

	dprintf("xid %08x secs %d ", bootp.xid, ntohs(bootp.secs));

	if (vendor_class_identifier_len > 2) {
		vec[i].iov_base = vendor_class_identifier;
		vec[i].iov_len  = vendor_class_identifier_len;
		i++;

		dprintf("vendor_class_identifier \"%.*s\" ",
			vendor_class_identifier_len-2,
			vendor_class_identifier+2);
	}

	if (dev->reqhostname[0] != '\0') {
		int len = strlen(dev->reqhostname);
		dhcp_hostname[0] = 12;
		dhcp_hostname[1] = len;
		memcpy(dhcp_hostname+2, dev->reqhostname, len);

		vec[i].iov_base = dhcp_hostname;
		vec[i].iov_len  = len+2;
		i++;

		printf("hostname %.*s ", len, dhcp_hostname+2);
	}

	vec[i].iov_base = dhcp_end;
	vec[i].iov_len  = sizeof(dhcp_end);

	/* Append padding if DHCP packet length is shorter than BOOTP_MIN_LEN */
	padding_len = sizeof(padding);
	for (j = 2; j <= i; j++)
		padding_len -= vec[j].iov_len;
	if (padding_len > 0) {
		memset(padding, 0, padding_len);
		i++;
		vec[i].iov_base = padding;
		vec[i].iov_len  = padding_len;
	}

	return packet_send(dev, vec, i + 1);
}

/*
 * Send a DHCP discover packet
 */
int dhcp_send_discover(struct netdev *dev)
{
	dev->ip_addr = INADDR_ANY;
	dev->ip_gateway = INADDR_ANY;

	dprintf("-> dhcp discover ");

	return dhcp_send(dev, dhcp_discover_iov);
}

/*
 * Receive a DHCP offer packet
 */
int dhcp_recv_offer(struct netdev *dev)
{
	return dhcp_recv(dev);
}

/*
 * Send a DHCP request packet
 */
int dhcp_send_request(struct netdev *dev)
{
	memcpy(&dhcp_request_hdr[SERVER_IP_OFF], &dev->serverid, 4);
	memcpy(&dhcp_request_hdr[REQ_IP_OFF], &dev->ip_addr, 4);

	dprintf("-> dhcp request ");

	return dhcp_send(dev, dhcp_request_iov);
}

/*
 * Receive a DHCP ack packet
 */
int dhcp_recv_ack(struct netdev *dev)
{
	return dhcp_recv(dev);
}
