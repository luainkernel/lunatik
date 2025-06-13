/*
 * libc_init.c
 *
 * This function takes the raw data block set up by the ELF loader
 * in the kernel and parses it.  It is invoked by crt0.S which makes
 * any necessary adjustments and passes calls this function using
 * the standard C calling convention.
 *
 * The arguments are:
 *  uintptr_t *elfdata	 -- The ELF loader data block; usually from the stack.
 *                          Basically a pointer to argc.
 *  void (*onexit)(void) -- Function to install into onexit
 */

/*
 * Several Linux ABIs don't pass the onexit pointer, and the ones that
 * do never use it.  Therefore, unless USE_ONEXIT is defined, we just
 * ignore the onexit pointer.
 */
/* #define USE_ONEXIT */

#include <stddef.h>
#include <stdlib.h>
#include <stdint.h>
#include <klibc/compiler.h>
#include <elf.h>
#include <sys/auxv.h>
#include <klibc/sysconfig.h>
#include "atexit.h"

#if _KLIBC_HAS_ARCHINIT
# include "klibc/archinit.h"
#else
# define __libc_archinit() ((void)0)
#endif

/* This file is included from __static_init.c or __shared_init.c */
#ifndef SHARED
# error "SHARED should be defined to 0 or 1"
#endif

char **environ;
unsigned int __page_size, __page_shift;

struct auxentry {
	unsigned long type;
	unsigned long v;
};

extern void __libc_init_stdio(void);

unsigned long __auxval[_AUXVAL_MAX];

__noreturn __libc_init(uintptr_t * elfdata, void (*onexit) (void))
{
	int argc;
	char **argv, **envp, **envend;
	struct auxentry *auxentry;
#if SHARED
	typedef int (*main_t) (int, char **, char **);
	main_t MAIN = NULL;
#else
	extern int main(int, char **, char **);
#define MAIN main
#endif
	unsigned int page_size = 0, page_shift = 0;

#ifdef USE_ONEXIT
	if (onexit) {
		static struct atexit at_exit;

		at_exit.fctn = (void (*)(int, void *))onexit;
		/* at_exit.next = NULL already */
		__atexit_list = &at_exit;
	}
#else
	(void)onexit;		/* Ignore this... */
#endif

	argc = (int)*elfdata++;
	argv = (char **)elfdata;
	envp = argv + (argc + 1);

	/* The auxillary entry vector is after all the environment vars */
	for (envend = envp; *envend; envend++) ;
	auxentry = (struct auxentry *)(envend + 1);

	while (auxentry->type) {
		if (auxentry->type < _AUXVAL_MAX)
			__auxval[auxentry->type] = auxentry->v;
		auxentry++;
	}

#if SHARED
	MAIN = (main_t) __auxval[AT_ENTRY];
#endif

	__page_size = page_size = __auxval[AT_PAGESZ];

#if __GNUC__ >= 4
	/* unsigned int is 32 bits on all our architectures */
	page_shift = __builtin_clz(page_size) ^ 31;
#elif defined(__i386__) || defined(__x86_64__)
	asm("bsrl %1,%0" : "=r" (page_shift) : "r" (page_size));
#else
	while (page_size > 1) {
		page_shift++;
		page_size >>= 1;
	}
#endif
	__page_shift = page_shift;

#if _KLIBC_HAS_ARCHINIT
	__libc_archinit();
#endif

	__libc_init_stdio();

	environ = envp;
	exit(MAIN(argc, argv, envp));
}
