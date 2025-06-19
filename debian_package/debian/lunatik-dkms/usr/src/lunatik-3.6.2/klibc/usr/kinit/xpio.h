/*
 * kinit/xpio.h
 */

#ifndef KINIT_XPIO_H
#define KINIT_XPIO_H

ssize_t xpread(int fd, void *buf, size_t count, off_t offset);
ssize_t xpwrite(int fd, void *buf, size_t count, off_t offset);

#endif				/* KINIT_XPIO_H */
