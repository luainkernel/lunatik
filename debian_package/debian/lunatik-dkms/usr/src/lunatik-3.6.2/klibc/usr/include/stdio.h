/*
 * stdio.h
 */

#ifndef _STDIO_H
#define _STDIO_H

#include <klibc/extern.h>
#include <klibc/sysconfig.h>
#include <klibc/seek.h>
#include <stdarg.h>
#include <stddef.h>
#include <unistd.h>

struct _IO_file {
	int _IO_fileno;		/* Underlying file descriptor */
	_Bool _IO_eof;		/* End of file flag */
	_Bool _IO_error;	/* Error flag */
};
typedef struct _IO_file FILE;

#ifndef EOF
# define EOF (-1)
#endif

#ifndef BUFSIZ
# define BUFSIZ _KLIBC_BUFSIZ
#endif

enum _IO_bufmode {
	_IONBF,
	_IOLBF,
	_IOFBF
};
#define _IONBF _IONBF
#define _IOLBF _IOLBF
#define _IOFBF _IOFBF

/*
 * Convert between a FILE * and a file descriptor.
 */
__extern FILE *stdin, *stdout, *stderr;

__extern FILE *fopen(const char *, const char *);
__extern FILE *fdopen(int, const char *);
__extern int fclose(FILE *);
__extern int fseek(FILE *, off_t, int);
#define fseeko fseek
__extern void rewind(FILE *);
__extern int fputs(const char *, FILE *);
__extern int fputs_unlocked(const char *, FILE *);
__extern int puts(const char *);
__extern int fputc(int, FILE *);
__extern int fputc_unlocked(int, FILE *);
#define putc(c,f)  fputc((c),(f))
#define putc_unlocked(c,f)  putc((c),(f))
#define putchar(c) fputc((c),stdout)
#define putchar_unlocked(c) putchar(c)

__extern int fgetc(FILE *);
__extern int fgetc_unlocked(FILE *);
__extern char *fgets(char *, int, FILE *);
__extern char *fgets_unlocked(char *, int, FILE *);
#define getc(f) fgetc(f)
__extern int getc_unlocked(FILE *);
#define getc_unlocked(f) fgetc(f)
#define getchar() fgetc(stdin)
#define getchar_unlocked() getchar()
__extern int ungetc(int, FILE *);

__extern int printf(const char *, ...);
__extern int vprintf(const char *, va_list);
__extern int fprintf(FILE *, const char *, ...);
__extern int vfprintf(FILE *, const char *, va_list);
__extern int sprintf(char *, const char *, ...);
__extern int vsprintf(char *, const char *, va_list);
__extern int snprintf(char *, size_t n, const char *, ...);
__extern int vsnprintf(char *, size_t n, const char *, va_list);
__extern int asprintf(char **, const char *, ...);
__extern int vasprintf(char **, const char *, va_list);

__extern int sscanf(const char *, const char *, ...);
__extern int vsscanf(const char *, const char *, va_list);

__extern void perror(const char *);

__extern int rename(const char *, const char *);
__extern int renameat(int, const char *, int, const char *);
__extern int renameat2(int, const char *, int, const char *, unsigned int);

__extern int remove(const char *);

__extern size_t _fread(void *, size_t, FILE *);
__extern size_t _fwrite(const void *, size_t, FILE *);
__extern int fflush(FILE *);
__extern int fflush_unlocked(FILE *);

__extern size_t fread(void *, size_t, size_t, FILE *);
__extern size_t fread_unlocked(void *, size_t, size_t, FILE *);
__extern size_t fwrite(const void *, size_t, size_t, FILE *);
__extern size_t fwrite_unlocked(const void *, size_t, size_t, FILE *);

__extern off_t ftell(FILE *__f);
#define ftello ftell

__extern int ferror(FILE * );
__extern int ferror_unlocked(FILE * );
__extern int feof(FILE *);
__extern int feof_unlocked(FILE *);
__extern int fileno(FILE *);
__extern int fileno_unlocked(FILE *);
__extern void clearerr(FILE *);
__extern void clearerr_unlocked(FILE *);

#ifndef __NO_STDIO_INLINES
__extern_inline size_t
fread(void *__p, size_t __s, size_t __n, FILE * __f)
{
	return _fread(__p, __s * __n, __f) / __s;
}
#define fread_unlocked(p, s, n, f) fread((p), (s), (n), (f))

__extern_inline size_t
fwrite(const void *__p, size_t __s, size_t __n, FILE * __f)
{
	return _fwrite(__p, __s * __n, __f) / __s;
}
#define fwrite_unlocked(p, s, n, f) fwrite((p), (s), (n), (f))

__extern_inline int fileno(FILE *__f)
{
	return __f->_IO_fileno;
}
#define fileno_unlocked(f) fileno(f)

__extern_inline int ferror(FILE *__f)
{
	return __f->_IO_error;
}
#define ferror_unlocked(f) ferror(f)

__extern_inline int feof(FILE *__f)
{
	return __f->_IO_eof;
}
#define feof_unlocked(f) feof(f)

__extern_inline void clearerr(FILE *__f)
{
	__f->_IO_error = 0;
	__f->_IO_eof = 0;
}
#define clearerr_unlocked(f) clearerr(f)
#endif

#endif				/* _STDIO_H */
