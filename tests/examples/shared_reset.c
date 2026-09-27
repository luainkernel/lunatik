/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Userspace peer for the shared example test (see shared.sh): sets a key, resets
* a session that asked for it, and exits 0 when a later session still reads the
* key's value from the daemon.
*/

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>

#define PORT	90
#define TIMEOUT	2
#define BUFSIZE	64

static int session(const char *request)
{
	struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons(PORT),
		.sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
	struct timeval timeout = {.tv_sec = TIMEOUT};
	int fd = socket(AF_INET, SOCK_STREAM, 0);

	if (fd < 0) {
		perror("socket");
		return -1;
	}
	if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0 ||
	    connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    send(fd, request, strlen(request), 0) < 0) {
		perror(request);
		close(fd);
		return -1;
	}
	return fd;
}

int main(void)
{
	char reply[BUFSIZE];
	ssize_t n;
	int fd;

	if ((fd = session("rst=x\n")) < 0)
		return 1;
	close(fd);

	if ((fd = session("rst\n")) < 0)
		return 1;
	n = recv(fd, reply, sizeof(reply), MSG_PEEK);
	close(fd); /* with the reply unread, the data_was_unread arm of tcp_close resets the connection */
	if (n <= 0) {
		fprintf(stderr, "no reply to the session the peer reset\n");
		return 1;
	}

	if ((fd = session("rst\n")) < 0)
		return 1;
	n = recv(fd, reply, sizeof(reply), 0);
	close(fd);
	if (n <= 0) {
		fprintf(stderr, "no reply after the reset\n");
		return 1;
	}
	return 0;
}

