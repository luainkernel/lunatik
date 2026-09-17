/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Userspace peer for the socket scmrights test (see scmrights.sh): listens on
* the AF_UNIX path given as argv[1], accepts one connection, reads its greeting
* and answers with one byte carrying the write end of a pipe as SCM_RIGHTS,
* the ancillary data a kernel-space receive must not hand a control buffer to.
* It then keeps only the read end, so the receive that drops the ancillary data
* releases the last write reference and the read reports EOF, while one that
* warns leaks the file and the read never returns.
*/

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define GREETING_MAX 8

/* binds and listens on `path`, replacing whatever is there; returns the fd, or -1 */
static int listener(const char *path)
{
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);

	snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);
	unlink(addr.sun_path);
	if (fd < 0 ||
	    bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    listen(fd, 1) < 0) {
		perror("listener");
		close(fd);
		return -1;
	}

	return fd;
}

/* sends one byte with `passed` attached as SCM_RIGHTS; returns 0 on success */
static int sendfd(int conn, int passed)
{
	union {
		struct cmsghdr cmsg;
		char buf[CMSG_SPACE(sizeof(int))];
	} control;
	char byte = 'x';
	struct iovec iov = { .iov_base = &byte, .iov_len = sizeof(byte) };
	struct msghdr msg;
	struct cmsghdr *cmsg = &control.cmsg;

	memset(&msg, 0, sizeof(msg));
	memset(&control, 0, sizeof(control));
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;
	msg.msg_control = &control;
	msg.msg_controllen = sizeof(control);

	cmsg->cmsg_level = SOL_SOCKET;
	cmsg->cmsg_type = SCM_RIGHTS;
	cmsg->cmsg_len = CMSG_LEN(sizeof(passed));
	memcpy(CMSG_DATA(cmsg), &passed, sizeof(passed));

	if (sendmsg(conn, &msg, 0) < 0) {
		perror("sendmsg");
		return 1;
	}

	return 0;
}

/* the receiver holds the only write end left, so EOF is it releasing the file */
static int waiteof(int fd)
{
	char byte;
	ssize_t n = read(fd, &byte, sizeof(byte));

	if (n != 0) {
		fprintf(stderr, "the passed descriptor outlived the receive (%zd)\n", n);
		return 1;
	}

	puts("released");
	fflush(stdout);
	return 0;
}

int main(int argc, char **argv)
{
	char greeting[GREETING_MAX];
	int fd, conn, pipefd[2], rc = 1;

	if (argc != 2) {
		fprintf(stderr, "usage: %s <path>\n", argv[0]);
		return 1;
	}

	if (pipe(pipefd) < 0) {
		perror("pipe");
		return 1;
	}

	fd = listener(argv[1]);
	if (fd < 0) {
		close(pipefd[0]);
		close(pipefd[1]);
		return 1;
	}

	/* the path is listening; the harness waits for this before the script connects */
	puts("listening");
	fflush(stdout);

	conn = accept(fd, NULL, NULL);
	if (conn < 0)
		perror("accept");
	else if (read(conn, greeting, sizeof(greeting)) < 0)
		perror("read");
	else
		rc = sendfd(conn, pipefd[1]);

	if (conn >= 0)
		close(conn);
	close(fd);
	close(pipefd[1]);
	unlink(argv[1]);

	if (rc == 0)
		rc = waiteof(pipefd[0]);
	close(pipefd[0]);
	return rc;
}

