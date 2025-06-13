#ifndef IPCONFIG_BOOTP_PROTO_H
#define IPCONFIG_BOOTP_PROTO_H

int bootp_send_request(struct netdev *dev);
int bootp_recv_reply(struct netdev *dev);
int bootp_parse(struct netdev *dev, struct bootp_hdr *hdr, uint8_t * exts,
		int extlen);
int bootp_init_if(struct netdev *dev);

#endif /* IPCONFIG_BOOTP_PROTO_H */
