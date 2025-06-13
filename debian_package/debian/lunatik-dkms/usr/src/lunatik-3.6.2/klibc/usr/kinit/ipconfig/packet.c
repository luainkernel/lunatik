#include <errno.h>/*XXX*/
/*
 * Packet socket handling glue.
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <net/if_packet.h>
#include <netinet/if_ether.h>
#include <netinet/in.h>
#include <netpacket/packet.h>
#include <asm/byteorder.h>
#include <arpa/inet.h>
#include <netinet/ip.h>
#include <netinet/udp.h>

#include "ipconfig.h"
#include "netdev.h"
#include "packet.h"

uint16_t cfg_local_port = LOCAL_PORT;
uint16_t cfg_remote_port = REMOTE_PORT;

int packet_open(struct netdev *dev)
{
	struct sockaddr_ll sll;
	int fd, rv, one = 1;

	/*
	 * Get a PACKET socket for IP traffic.
	 */
	fd = socket(AF_PACKET, SOCK_DGRAM, htons(ETH_P_IP));
	if (fd == -1) {
		perror("socket");
		return -1;
	}

	/*
	 * We want to broadcast
	 */
	if (setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one,
		       sizeof(one)) == -1) {
		perror("SO_BROADCAST");
		close(fd);
		return -1;
	}

	memset(&sll, 0, sizeof(sll));
	sll.sll_family = AF_PACKET;
	sll.sll_ifindex = dev->ifindex;

	rv = bind(fd, (struct sockaddr *)&sll, sizeof(sll));
	if (-1 == rv) {
		perror("bind");
		close(fd);
		return -1;
	}

	dev->pkt_fd = fd;
	return fd;
}

void packet_close(struct netdev *dev)
{
	close(dev->pkt_fd);
	dev->pkt_fd = -1;
}

static unsigned int ip_checksum(uint16_t *hdr, int len)
{
	unsigned int chksum = 0;

	while (len) {
		chksum += *hdr++;
		chksum += *hdr++;
		len--;
	}
	chksum = (chksum & 0xffff) + (chksum >> 16);
	chksum = (chksum & 0xffff) + (chksum >> 16);
	return (~chksum) & 0xffff;
}

struct header {
	struct iphdr ip;
	struct udphdr udp;
} __attribute__ ((packed, aligned(4)));

static struct header ipudp_hdrs = {
	.ip = {
	       .ihl		= 5,
	       .version		= IPVERSION,
	       .frag_off	= __constant_htons(IP_DF),
	       .ttl		= 64,
	       .protocol	= IPPROTO_UDP,
	       .saddr		= INADDR_ANY,
	       .daddr		= INADDR_BROADCAST,
	       },
	.udp = {
		.source		= __constant_htons(LOCAL_PORT),
		.dest		= __constant_htons(REMOTE_PORT),
		.len		= 0,
		.check		= 0,
		},
};

#ifdef DEBUG /* Only used with dprintf() */
static char *ntoa(uint32_t addr)
{
	struct in_addr in = { addr };
	return inet_ntoa(in);
}
#endif /* DEBUG */

/*
 * Send a packet.  The options are listed in iov[1...iov_len-1].
 * iov[0] is reserved for the bootp packet header.
 */
int packet_send(struct netdev *dev, struct iovec *iov, int iov_len)
{
	struct sockaddr_ll sll;
	struct msghdr msg;
	int i, len = 0;

	memset(&sll, 0, sizeof(sll));
	msg.msg_name = &sll;
	msg.msg_namelen = sizeof(sll);
	msg.msg_iov = iov;
	msg.msg_iovlen = iov_len;
	msg.msg_control = NULL;
	msg.msg_controllen = 0;
	msg.msg_flags = 0;

	if (cfg_local_port != LOCAL_PORT) {
		ipudp_hdrs.udp.source = htons(cfg_local_port);
		ipudp_hdrs.udp.dest = htons(cfg_remote_port);
	}

	dprintf("\n   udp src %d dst %d", ntohs(ipudp_hdrs.udp.source),
		ntohs(ipudp_hdrs.udp.dest));

	dprintf("\n   ip src %s ", ntoa(ipudp_hdrs.ip.saddr));
	dprintf("dst %s ", ntoa(ipudp_hdrs.ip.daddr));

	/*
	 * Glue in the ip+udp header iovec
	 */
	iov[0].iov_base = &ipudp_hdrs;
	iov[0].iov_len = sizeof(struct header);

	for (i = 0; i < iov_len; i++)
		len += iov[i].iov_len;

	sll.sll_family	 = AF_PACKET;
	sll.sll_protocol = htons(ETH_P_IP);
	sll.sll_ifindex	 = dev->ifindex;
	sll.sll_hatype	 = dev->hwtype;
	sll.sll_pkttype	 = PACKET_BROADCAST;
	sll.sll_halen	 = dev->hwlen;
	memcpy(sll.sll_addr, dev->hwbrd, dev->hwlen);

	ipudp_hdrs.ip.tot_len = htons(len);
	ipudp_hdrs.ip.check   = 0;
	ipudp_hdrs.ip.check   = ip_checksum((uint16_t *) &ipudp_hdrs.ip,
					    ipudp_hdrs.ip.ihl);

	ipudp_hdrs.udp.len    = htons(len - sizeof(struct iphdr));

	dprintf("\n   bytes %d\n", len);

	return sendmsg(dev->pkt_fd, &msg, 0);
}

void packet_discard(struct netdev *dev)
{
	struct iphdr iph;
	struct sockaddr_ll sll;
	socklen_t sllen = sizeof(sll);

	sll.sll_ifindex = dev->ifindex;

	recvfrom(dev->pkt_fd, &iph, sizeof(iph), 0,
		 (struct sockaddr *)&sll, &sllen);
}

/*
 * Receive a bootp packet.  The options are listed in iov[1...iov_len].
 * iov[0] must point to the bootp packet header.
 * Returns:
 * -1 = Error, try again later
*   0 = Discarded packet (non-DHCP/BOOTP traffic)
 * >0 = Size of packet
 */
int packet_recv(struct netdev *dev, struct iovec *iov, int iov_len)
{
	struct iphdr *ip, iph;
	struct udphdr *udp;
	struct msghdr msg = {
		.msg_name	= NULL,
		.msg_namelen	= 0,
		.msg_iov	= iov,
		.msg_iovlen	= iov_len,
		.msg_control	= NULL,
		.msg_controllen = 0,
		.msg_flags	= 0
	};
	int ret, iphl;
	struct sockaddr_ll sll;
	socklen_t sllen = sizeof(sll);

	sll.sll_ifindex = dev->ifindex;
	msg.msg_name = &sll;
	msg.msg_namelen = sllen;

	ret = recvfrom(dev->pkt_fd, &iph, sizeof(struct iphdr),
		       MSG_PEEK, (struct sockaddr *)&sll, &sllen);
	if (ret == -1)
		return -1;

	if (iph.ihl < 5 || iph.version != IPVERSION)
		goto discard_pkt;

	iphl = iph.ihl * 4;

	ip = malloc(iphl + sizeof(struct udphdr));
	if (!ip)
		goto discard_pkt;

	udp = (struct udphdr *)((char *)ip + iphl);

	iov[0].iov_base = ip;
	iov[0].iov_len = iphl + sizeof(struct udphdr);

	ret = recvmsg(dev->pkt_fd, &msg, 0);
	if (ret == -1)
		goto free_pkt;

	dprintf("<- bytes %d ", ret);

	if (ip_checksum((uint16_t *) ip, ip->ihl) != 0)
		goto free_pkt;

	dprintf("\n   ip src %s ", ntoa(ip->saddr));
	dprintf("dst %s ", ntoa(ip->daddr));

	if (ntohs(ip->tot_len) > ret || ip->protocol != IPPROTO_UDP)
		goto free_pkt;

	ret -= 4 * ip->ihl;

	dprintf("\n   udp src %d dst %d ", ntohs(udp->source),
		ntohs(udp->dest));

	if (udp->source != htons(cfg_remote_port) ||
	    udp->dest != htons(cfg_local_port))
		goto free_pkt;

	if (ntohs(udp->len) > ret)
		goto free_pkt;

	ret -= sizeof(struct udphdr);

	free(ip);

	return ret;

free_pkt:
	dprintf("freed\n");
	free(ip);
	return 0;

discard_pkt:
	dprintf("discarded\n");
	packet_discard(dev);
	return 0;
}
