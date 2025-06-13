/*
 * ctype.h
 *
 * This assumes ISO 8859-1, being a reasonable superset of ASCII.
 */

#ifndef _CTYPE_H
#define _CTYPE_H

#include <klibc/extern.h>
#include <klibc/compiler.h>

/*
 * This relies on the following definitions:
 *
 * cntrl = !print
 * alpha = upper|lower
 * graph = punct|alpha|digit
 * blank = '\t' || ' ' (per POSIX requirement)
 */
enum {
	__ctype_upper = (1 << 0),
	__ctype_lower = (1 << 1),
	__ctype_digit = (1 << 2),
	__ctype_xdigit = (1 << 3),
	__ctype_space = (1 << 4),
	__ctype_print = (1 << 5),
	__ctype_punct = (1 << 6),
	__ctype_cntrl = (1 << 7),
};

__extern int isalnum(int);
__extern int isalpha(int);
__extern int isascii(int);
__extern int isblank(int);
__extern int iscntrl(int);
__extern int isdigit(int);
__extern int isgraph(int);
__extern int islower(int);
__extern int isprint(int);
__extern int ispunct(int);
__extern int isspace(int);
__extern int isupper(int);
__extern int isxdigit(int);
__extern int toupper(int);
__extern int tolower(int);

extern const unsigned char __ctypes[];

__must_inline int __ctype_isalnum(int);
__must_inline int __ctype_isalpha(int);
__must_inline int __ctype_isascii(int);
__must_inline int __ctype_isblank(int);
__must_inline int __ctype_iscntrl(int);
__must_inline int __ctype_isdigit(int);
__must_inline int __ctype_isgraph(int);
__must_inline int __ctype_islower(int);
__must_inline int __ctype_isprint(int);
__must_inline int __ctype_ispunct(int);
__must_inline int __ctype_isspace(int);
__must_inline int __ctype_isupper(int);
__must_inline int __ctype_isxdigit(int);

__must_inline int __ctype_isalnum(int __c)
{
	return __ctypes[__c + 1] &
	    (__ctype_upper | __ctype_lower | __ctype_digit);
}

__must_inline int __ctype_isalpha(int __c)
{
	return __ctypes[__c + 1] & (__ctype_upper | __ctype_lower);
}

__must_inline int __ctype_isascii(int __c)
{
	return !(__c & ~0x7f);
}

__must_inline int __ctype_isblank(int __c)
{
	return (__c == '\t') || (__c == ' ');
}

__must_inline int __ctype_iscntrl(int __c)
{
	return __ctypes[__c + 1] & __ctype_cntrl;
}

__must_inline int __ctype_isdigit(int __c)
{
	return ((unsigned)__c - '0') <= 9;
}

__must_inline int __ctype_isgraph(int __c)
{
	return __ctypes[__c + 1] &
	    (__ctype_upper | __ctype_lower | __ctype_digit | __ctype_punct);
}

__must_inline int __ctype_islower(int __c)
{
	return __ctypes[__c + 1] & __ctype_lower;
}

__must_inline int __ctype_isprint(int __c)
{
	return __ctypes[__c + 1] & __ctype_print;
}

__must_inline int __ctype_ispunct(int __c)
{
	return __ctypes[__c + 1] & __ctype_punct;
}

__must_inline int __ctype_isspace(int __c)
{
	return __ctypes[__c + 1] & __ctype_space;
}

__must_inline int __ctype_isupper(int __c)
{
	return __ctypes[__c + 1] & __ctype_upper;
}

__must_inline int __ctype_isxdigit(int __c)
{
	return __ctypes[__c + 1] & __ctype_xdigit;
}

/* Note: this is decimal, not hex, to avoid accidental promotion to unsigned */
#define _toupper(__c) ((__c) & ~32)
#define _tolower(__c) ((__c) | 32)

__must_inline int __ctype_toupper(int);
__must_inline int __ctype_tolower(int);

__must_inline int __ctype_toupper(int __c)
{
	return __ctype_islower(__c) ? _toupper(__c) : __c;
}

__must_inline int __ctype_tolower(int __c)
{
	return __ctype_isupper(__c) ? _tolower(__c) : __c;
}

#ifdef __CTYPE_NO_INLINE
# define __CTYPEFUNC(X) \
  __extern int X(int);
#else
#define __CTYPEFUNC(X) \
  __extern_inline int X(int __c)		\
  {						\
    return __ctype_##X(__c); 			\
  }
#endif

__CTYPEFUNC(isalnum)
__CTYPEFUNC(isalpha)
__CTYPEFUNC(isascii)
__CTYPEFUNC(isblank)
__CTYPEFUNC(iscntrl)
__CTYPEFUNC(isdigit)
__CTYPEFUNC(isgraph)
__CTYPEFUNC(islower)
__CTYPEFUNC(isprint)
__CTYPEFUNC(ispunct)
__CTYPEFUNC(isspace)
__CTYPEFUNC(isupper)
__CTYPEFUNC(isxdigit)
__CTYPEFUNC(toupper)
__CTYPEFUNC(tolower)
#endif				/* _CTYPE_H */
