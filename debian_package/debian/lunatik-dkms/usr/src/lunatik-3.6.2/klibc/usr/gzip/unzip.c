/* unzip.c -- decompress files in gzip or pkzip format.
 * Copyright (C) 1992-1993 Jean-loup Gailly
 * This is free software; you can redistribute it and/or modify it under the
 * terms of the GNU General Public License, see the file COPYING.
 *
 * The code in this file is derived from the file funzip.c written
 * and put in the public domain by Mark Adler.
 */

/*
   This version can extract files in gzip format.
   Only the first entry is extracted, and it has to be
   either deflated or stored.
 */

#ifdef RCSID
static char rcsid[] = "$Id: unzip.c,v 1.1 2002/08/18 00:59:21 hpa Exp $";
#endif

#include "tailor.h"
#include "gzip.h"

/* ===========================================================================
 * Unzip in to out.  This routine works on gzip files only.
 *
 * IN assertions: the buffer inbuf contains already the beginning of
 *   the compressed data, from offsets inptr to insize-1 included.
 *   The magic header has already been checked. The output buffer is cleared.
 */
int unzip(in, out)
    int in, out;   /* input and output file descriptors */
{
    ulg orig_crc = 0;       /* original crc */
    ulg orig_len = 0;       /* original uncompressed length */
    int n;
    uch buf[8];        /* extended local header */

    ifd = in;
    ofd = out;

    updcrc(NULL, 0);           /* initialize crc */

    /* Decompress */
    if (method == DEFLATED)  {

	int res = inflate();

	if (res == 3) {
	    error("out of memory");
	} else if (res != 0) {
	    error("invalid compressed data--format violated");
	}

    } else {
	error("internal error, invalid method");
    }

    /* Get the crc and original length */
    /* crc32  (see algorithm.doc)
     * uncompressed input size modulo 2^32
     */
    for (n = 0; n < 8; n++) {
	buf[n] = (uch)get_byte(); /* may cause an error if EOF */
    }
    orig_crc = LG(buf);
    orig_len = LG(buf+4);

    /* Validate decompression */
    if (orig_crc != updcrc(outbuf, 0)) {
	error("invalid compressed data--crc error");
    }
    if (orig_len != (ulg)bytes_out) {
	error("invalid compressed data--length error");
    }

    return OK;
}
