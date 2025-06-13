/*
 * klibc/sysconfig.h
 *
 * Allows for definitions of some things which may be system-dependent
 * NOTE: this file must not result in any output from the preprocessor.
 */

#ifndef _KLIBC_SYSCONFIG_H
#define _KLIBC_SYSCONFIG_H

#include <klibc/archconfig.h>
#include <asm/unistd.h>

/*
 * These are the variables that can be defined in <klibc/archconfig.h>.
 * For boolean options, #define to 0 to disable, #define to 1 to enable.
 *
 * If undefined, they will be given defaults here.
 */


/*
 * _KLIBC_NO_MMU:
 *
 *	Indicates this architecture doesn't have an MMU, and therefore
 *	does not have the sys_fork and sys_brk system calls.
 */
/* Default to having an MMU if we can find the fork system call */
#ifndef _KLIBC_NO_MMU
# if defined(__NR_fork)
#  define _KLIBC_NO_MMU 0
# else
#  define _KLIBC_NO_MMU 1
# endif
#endif


/*
 * _KLIBC_REAL_VFORK:
 *
 *	Indicates that this architecture has a real vfork() system call.
 *	This is the default if sys_vfork exists; if there is an
 *	architecture-dependent implementation of vfork(), define this
 *	symbol.
 */
#ifndef _KLIBC_REAL_VFORK
# if defined(__NR_vfork)
#  define _KLIBC_REAL_VFORK 1
# else
#  define _KLIBC_REAL_VFORK 0
# endif
#endif


/*
 * _KLIBC_USE_MMAP2:
 *
 *	Indicates that this architecture should use sys_mmap2 instead
 *	of sys_mmap.  This is the default on 32-bit architectures, assuming
 *	sys_mmap2 exists.
 */
#ifndef _KLIBC_USE_MMAP2
# if (_BITSIZE == 32 && defined(__NR_mmap2)) || \
     (_BITSIZE == 64 && !defined(__NR_mmap))
#  define _KLIBC_USE_MMAP2 1
# else
#  define _KLIBC_USE_MMAP2 0
# endif
#endif


/*
 * _KLIBC_MMAP2_SHIFT:
 *
 *	Indicate the shift of the offset parameter in sys_mmap2.
 *	On most architectures, this is always 12, but on some
 *	architectures it can be a different number, or the current
 *	page size.  If this is dependent on the page size, define
 *	this to an expression which includes __getpageshift().
 */
#ifndef _KLIBC_MMAP2_SHIFT
# define _KLIBC_MMAP2_SHIFT 12
#endif


/*
 * _KLIBC_MALLOC_USES_SBRK:
 *
 *	Indicates that malloc() should use sbrk() to obtain raw memory
 *	from the system, rather than mmap().
 */
/* Default to get memory using mmap() */
#ifndef _KLIBC_MALLOC_USES_SBRK
# define _KLIBC_MALLOC_USES_SBRK 0
#endif


/*
 * _KLIBC_MALLOC_CHUNK_SIZE:
 *	This is the minimum chunk size we will ask the kernel for using
 *	malloc(); this should be a multiple of the page size and must
 *	be a power of 2.
 */
#ifndef _KLIBC_MALLOC_CHUNK_SIZE
# define _KLIBC_MALLOC_CHUNK_SIZE	65536
#endif


/*
 * _KLIBC_BUFSIZ:
 *	This is the size of an stdio buffer.  By default this is
 *	_KLIBC_MALLOC_CHUNK_SIZE/4, which allows the three standard
 *	streams to fit inside a malloc chunk.
 */
#ifndef _KLIBC_BUFSIZ
# define _KLIBC_BUFSIZ (_KLIBC_MALLOC_CHUNK_SIZE >> 2)
#endif


/*
 * _KLIBC_SBRK_ALIGNMENT:
 *
 *	This is the minimum alignment for the memory returned by
 *	sbrk().  It must be a power of 2.  If _KLIBC_MALLOC_USES_SBRK
 *	is set it should be no smaller than the size of struct
 *	arena_header in malloc.h (== 4 pointers.)
 */
#ifndef _KLIBC_SBRK_ALIGNMENT
# define _KLIBC_SBRK_ALIGNMENT		32
#endif


/*
 * _KLIBC_NEEDS_SA_RESTORER:
 *
 *	Some architectures, like x86-64 and some i386 Fedora kernels,
 *	do not provide a default sigreturn, and therefore must have
 *	SA_RESTORER set.  On others, the default sigreturn requires an
 *	executable stack, which we should avoid.
 */
#ifndef _KLIBC_NEEDS_SA_RESTORER
# define _KLIBC_NEEDS_SA_RESTORER 0
#endif


/*
 * _KLIBC_NEEDS_SA_SIGINFO:
 *
 *	On some architectures, the signal stack frame is set up for
 *	either sigreturn() or rt_sigreturn() depending on whether
 *	SA_SIGINFO is set.  Where this is the case, and we provide our
 *	own restorer function, this must also be set so that the
 *	restorer can always use rt_sigreturn().
 */
#ifndef _KLIBC_NEEDS_SA_SIGINFO
# define _KLIBC_NEEDS_SA_SIGINFO 0
#endif


/*
 * _KLIBC_NEEDS_SIGACTION_FIXUP
 *
 *	On some architectures, struct sigaction needs additional
 *	changes before passing to the kernel.
 */
#ifndef _KLIBC_NEEDS_SIGACTION_FIXUP
# define _KLIBC_NEEDS_SIGACTION_FIXUP 0
#endif


/*
 * _KLIBC_STATFS_F_TYPE_64:
 *
 *	This indicates that the f_type, f_bsize, f_namelen,
 *	f_frsize, and f_spare fields of struct statfs are
 *	64 bits long.  This is normally the case for 64-bit
 *	platforms, and so is the default for those.  See
 *	usr/include/sys/vfs.h for the exact details.
 */
#ifndef _KLIBC_STATFS_F_TYPE_64
# define _KLIBC_STATFS_F_TYPE_64 (_BITSIZE == 64)
#endif


/*
 * _KLIBC_STATFS_F_TYPE_32B:
 *
 * 	mips has it's own definition of statfs, which is
 * 	different from any other 32 bit arch.
 */
#ifndef _KLIBC_STATFS_F_TYPE_32B
# define _KLIBC_STATFS_F_TYPE_32B 0
#endif


/*
 * _KLIBC_HAS_ARCHSOCKET_H
 *
 *       This architecture has <klibc/archsocket.h>
 */
#ifndef _KLIBC_HAS_ARCHSOCKET_H
# define _KLIBC_HAS_ARCHSOCKET_H 0
#endif


/*
 * _KLIBC_SYS_SOCKETCALL
 *
 *	This architecture (e.g. SPARC) advertises socket-related
 *	system calls, which are not actually implemented.  Use
 *	socketcalls unconditionally instead.
 */
#ifndef _KLIBC_SYS_SOCKETCALL
# define _KLIBC_SYS_SOCKETCALL 0
#endif

/*
 * _KLIBC_ARM_USE_BX
 *
 *	This arm architecture supports bx instruction.
 */
#ifndef _KLIBC_ARM_USE_BX
# define _KLIBC_ARM_USE_BX 0
#endif

/*
 * _KLIBC_HAS_ARCHINIT
 *
 *	This architecture has klibc/archinit.h and __libc_archinit()
 */
#ifndef _KLIBC_HAS_ARCHINIT
# define _KLIBC_HAS_ARCHINIT 0
#endif

#endif /* _KLIBC_SYSCONFIG_H */
