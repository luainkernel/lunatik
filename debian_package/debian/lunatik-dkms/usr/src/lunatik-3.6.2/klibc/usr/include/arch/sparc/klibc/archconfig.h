/*
 * include/arch/sparc/klibc/archconfig.h
 *
 * See include/klibc/sysconfig.h for the options that can be set in
 * this file.
 *
 */

#ifndef _KLIBC_ARCHCONFIG_H
#define _KLIBC_ARCHCONFIG_H

#define _KLIBC_SYS_SOCKETCALL 1 /* Use sys_socketcall unconditionally */

/* So that we can avoid stack trampolines */
#define _KLIBC_NEEDS_SA_RESTORER 1
/* Our restorer will call rt_sigreturn() */
#define _KLIBC_NEEDS_SA_SIGINFO 1

#endif				/* _KLIBC_ARCHCONFIG_H */
