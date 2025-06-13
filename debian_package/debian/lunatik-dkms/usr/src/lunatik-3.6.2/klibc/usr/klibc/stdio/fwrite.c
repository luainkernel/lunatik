/*
 * fwrite.c
 */

#include <string.h>
#include "stdioint.h"

static size_t fwrite_noflush(const void *buf, size_t count,
			     struct _IO_file_pvt *f)
{
	size_t bytes = 0;
	size_t nb;
	const char *p = buf;
	ssize_t rv;

	while (count) {
		if (f->ibytes || f->obytes >= f->bufsiz ||
		    (f->obytes && count >= f->bufsiz))
			if (__fflush(f))
				break;

		if (count >= f->bufsiz) {
			/*
			 * The write is large, so bypass
			 * buffering entirely.
			 */
			rv = write(f->pub._IO_fileno, p, count);
			if (rv == -1) {
				if (errno == EINTR || errno == EAGAIN)
					continue;
				f->pub._IO_error = true;
				break;
			} else if (rv == 0) {
				/* EOF on output? */
				f->pub._IO_eof = true;
				break;
			}

			p += rv;
			bytes += rv;
			count -= rv;
		} else {
			nb = f->bufsiz - f->obytes;
			nb = (count < nb) ? count : nb;
			if (nb) {
				memcpy(f->buf+f->obytes, p, nb);
				p += nb;
				f->obytes += nb;
				count -= nb;
				bytes += nb;
			}
		}
	}
	return bytes;
}

size_t _fwrite(const void *buf, size_t count, FILE *file)
{
	struct _IO_file_pvt *f = stdio_pvt(file);
	size_t bytes = 0;
	size_t pf_len, pu_len;
	const char *p = buf;
	const char *q;

	/* We divide the data into two chunks, flushed (pf)
	   and unflushed (pu) depending on buffering mode
	   and contents. */

	switch (f->bufmode) {
	case _IOFBF:
		pf_len = 0;
		break;

	case _IOLBF:
		q = memrchr(p, '\n', count);
		pf_len = q ? q - p + 1 : 0;
		break;

	case _IONBF:
	default:
		pf_len = count;
		break;
	}

	if (pf_len) {
		bytes = fwrite_noflush(p, pf_len, f);
		p += bytes;
		if (__fflush(f) || bytes != pf_len)
			return bytes;
	}

	pu_len = count - pf_len;
	if (pu_len)
		bytes += fwrite_noflush(p, pu_len, f);

	return bytes;
}
