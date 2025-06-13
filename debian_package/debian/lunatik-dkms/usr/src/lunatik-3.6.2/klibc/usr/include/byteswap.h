/*
 * byteswap.h
 */

#ifndef _BYTESWAP_H
#define _BYTESWAP_H

#include <sys/types.h>
#include <asm/byteorder.h>

#define bswap_16(x) __swab16(x)
#define bswap_32(x) __swab32(x)
#define bswap_64(x) __swab64(x)

#endif				/* _BYTESWAP_H */
