#ifndef BOOTP_PACKET_H
#define BOOTP_PACKET_H

#include <sys/uio.h>

struct netdev;

/* packet ops */
#define BOOTP_REQUEST	1
#define BOOTP_REPLY	2

/* your basic bootp packet */
struct bootp_hdr {
	uint8_t	 op;
	uint8_t	 htype;
	uint8_t	 hlen;
	uint8_t	 hops;
	uint32_t xid;
	uint16_t secs;
	uint16_t flags;
	uint32_t ciaddr;
	uint32_t yiaddr;
	uint32_t siaddr;
	uint32_t giaddr;
	uint8_t	 chaddr[16];
	char	 server_name[64];
	char	 boot_file[128];
	/* 312 bytes of extensions */
};

/*
 * memory size of BOOTP Vendor Extensions/DHCP Options for receiving
 *
 * generic_ether_mtu:1500, min_sizeof(ip_hdr):20, sizeof(udp_hdr):8
 *
 * #define BOOTP_EXTS_SIZE	(1500 - 20 - 8 - sizeof(struct bootp_hdr))
 */
/* larger size for backward compatibility of ipconfig */
#define BOOTP_EXTS_SIZE	1500

/* minimum length of BOOTP/DHCP packet on sending */
#define BOOTP_MIN_LEN	300

#endif /* BOOTP_PACKET_H */
