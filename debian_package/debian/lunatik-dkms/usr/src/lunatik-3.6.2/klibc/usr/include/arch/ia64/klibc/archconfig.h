/*
 * include/arch/ia64/klibc/archconfig.h
 *
 * See include/klibc/sysconfig.h for the options that can be set in
 * this file.
 *
 */

#ifndef _KLIBC_ARCHCONFIG_H
#define _KLIBC_ARCHCONFIG_H

/* IA64 doesn't have sys_fork, but it does have an MMU */
#define _KLIBC_NO_MMU 0
/* IA64 doesn't have sys_vfork, it has architecture-specific code */
#define _KLIBC_REAL_VFORK 1
/* Need to fix-up function pointers to function descriptor pointers
 * in struct sigaction */
#define _KLIBC_NEEDS_SIGACTION_FIXUP 1

#endif				/* _KLIBC_ARCHCONFIG_H */
