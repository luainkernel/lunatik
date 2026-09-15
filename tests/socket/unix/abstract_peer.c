/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Userspace peer for the socket.unix abstract address test (see abstract.sh):
* "connect <name>" reaches the name a kernel script bound and prints the reply,
* "serve <name>" binds <name> for STREAM and <name>dgram for DGRAM and prints
* what each one received. A name registered as anything but the bytes the script
* gave is a name this peer cannot spell, and every case here then fails.
*/

#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>

#define TIMEOUT	5
#define BUFSIZE	64

/* an abstract address is the leading NUL and the name, with no terminator */
static socklen_t abstract_addr(struct sockaddr_un *addr, const char *name)
{
	size_t len = strnlen(name, sizeof(addr->sun_path) - 1);

	memset(addr, 0, sizeof(*addr));
	addr->sun_family = AF_UNIX;
	memcpy(addr->sun_path + 1, name, len);

	return offsetof(struct sockaddr_un, sun_path) + 1 + len;
}

static int bind_abstract(const char *name, int type)
{
	struct sockaddr_un addr;
	socklen_t len = abstract_addr(&addr, name);
	struct timeval tv = { .tv_sec = TIMEOUT };
	int fd = socket(AF_UNIX, type, 0);

	if (fd < 0) {
		perror("socket");
		return -1;
	}

	if (bind(fd, (struct sockaddr *)&addr, len) < 0 ||
	    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
		perror("bind");
		close(fd);
		return -1;
	}

	return fd;
}

static int peer_connect(const char *name)
{
	struct sockaddr_un addr;
	socklen_t len = abstract_addr(&addr, name);
	struct timeval tv = { .tv_sec = TIMEOUT };
	char buf[BUFSIZE];
	ssize_t n;
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);

	if (fd < 0) {
		perror("socket");
		return 1;
	}

	if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0 ||
	    connect(fd, (struct sockaddr *)&addr, len) < 0 ||
	    send(fd, "ping", 4, 0) < 0) {
		perror("connect");
		close(fd);
		return 1;
	}

	n = recv(fd, buf, sizeof(buf) - 1, 0);
	close(fd);
	if (n < 0) {
		perror("recv");
		return 1;
	}

	buf[n] = '\0';
	printf("%s\n", buf);
	return 0;
}

static int peer_serve(const char *name)
{
	char dgram_name[BUFSIZE];
	char buf[BUFSIZE];
	int stream_fd, dgram_fd, session;
	ssize_t n;

	snprintf(dgram_name, sizeof(dgram_name), "%sdgram", name);
	stream_fd = bind_abstract(name, SOCK_STREAM);
	dgram_fd = bind_abstract(dgram_name, SOCK_DGRAM);
	if (stream_fd < 0 || dgram_fd < 0 || listen(stream_fd, 1) < 0) {
		perror("serve");
		return 1;
	}

	/* both names are bound; the harness waits for this before running the client */
	fprintf(stderr, "READY\n");
	fflush(stderr);

	session = accept(stream_fd, NULL, NULL);
	if (session < 0) {
		perror("accept");
		return 1;
	}

	n = recv(session, buf, sizeof(buf) - 1, 0);
	if (n > 0) {
		buf[n] = '\0';
		const char *reply = strcmp(buf, "ping") == 0 ? "pong" : "unexpected";

		send(session, reply, strlen(reply), 0);
	}
	close(session);

	n = recv(dgram_fd, buf, sizeof(buf) - 1, 0);
	if (n < 0) {
		perror("recv");
		return 1;
	}

	buf[n] = '\0';
	printf("datagram: %s\n", buf);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc == 3 && strcmp(argv[1], "connect") == 0)
		return peer_connect(argv[2]);
	if (argc == 3 && strcmp(argv[1], "serve") == 0)
		return peer_serve(argv[2]);

	fprintf(stderr, "usage: %s connect|serve <name>\n", argv[0]);
	return 1;
}

