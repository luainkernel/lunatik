/*
 * fread.c
 */

#include <stdbool.h>
#include <string.h>
#include "stdioint.h"

size_t _fread(void *buf, size_t count, FILE *file)
{
	struct _IO_file_pvt *f = stdio_pvt(file);
	size_t bytes = 0;
	size_t nb;
	char *p = buf;
	char *rdptr;
	ssize_t rv;
	bool bypass;

	if (!count)
		return 0;

	if (f->obytes)		/* User error! */
		__fflush(f);

	while (count) {
		while (f->ibytes == 0) {
			/*
			 * The buffer is empty, we have to read
			 */
			bypass = (count >= f->bufsiz);
			if (bypass) {
				/* Large read, bypass buffer */
				rdptr = p;
				nb = count;
			} else {
				rdptr = f->buf + _IO_UNGET_SLOP;
				nb = f->bufsiz;
			}

			rv = read(f->pub._IO_fileno, rdptr, nb);
			if (rv == -1) {
				if (errno == EINTR || errno == EAGAIN)
					continue;
				f->pub._IO_error = true;
				return bytes;
			} else if (rv == 0) {
				f->pub._IO_eof = true;
				return bytes;


			}

			if (bypass) {
				p += rv;
				bytes += rv;
				count -= rv;
			} else {
				f->ibytes = rv;
				f->data = rdptr;
			}

			if (!count)
				return bytes;
		}

		/* If we get here, the buffer is non-empty */
		nb = f->ibytes;
		nb = (count < nb) ? count : nb;
		if (nb) {
			memcpy(p, f->data, nb);
			p += nb;
			bytes += nb;
			count -= nb;
			f->data += nb;
			f->ibytes -= nb;
		}
	}
	return bytes;
}
