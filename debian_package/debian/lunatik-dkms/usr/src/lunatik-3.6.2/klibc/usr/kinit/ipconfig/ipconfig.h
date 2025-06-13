#ifndef IPCONFIG_IPCONFIG_H
#define IPCONFIG_IPCONFIG_H

#include <stdint.h>
#include <sys/types.h>

#define LOCAL_PORT	68
#define REMOTE_PORT	(LOCAL_PORT - 1)

extern uint16_t cfg_local_port;
extern uint16_t cfg_remote_port;

extern char vendor_class_identifier[];
extern int vendor_class_identifier_len;

int ipconfig_main(int argc, char *argv[]);
uint32_t ipconfig_server_address(void *next);

#ifdef DEBUG
# define dprintf printf
#else
# define dprintf(...) ((void)0)
#endif

#endif /* IPCONFIG_IPCONFIG_H */
