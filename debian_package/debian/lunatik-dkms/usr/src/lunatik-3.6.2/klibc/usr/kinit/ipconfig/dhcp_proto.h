#ifndef IPCONFIG_DHCP_PROTO_H
#define IPCONFIG_DHCP_PROTO_H

/* DHCP message types */
#define DHCPDISCOVER    1
#define DHCPOFFER       2
#define DHCPREQUEST     3
#define DHCPDECLINE     4
#define DHCPACK         5
#define DHCPNAK         6
#define DHCPRELEASE     7
#define DHCPINFORM      8

int dhcp_send_discover(struct netdev *dev);
int dhcp_recv_offer(struct netdev *dev);
int dhcp_send_request(struct netdev *dev);
int dhcp_recv_ack(struct netdev *dev);

#endif /* IPCONFIG_DHCP_PROTO_H */
