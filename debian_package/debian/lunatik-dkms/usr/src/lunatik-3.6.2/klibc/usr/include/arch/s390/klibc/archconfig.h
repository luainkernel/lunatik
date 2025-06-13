/*
 * include/arch/s390/klibc/archconfig.h
 *
 * See include/klibc/sysconfig.h for the options that can be set in
 * this file.
 *
 */

#ifndef _KLIBC_ARCHCONFIG_H
#define _KLIBC_ARCHCONFIG_H

/* Both s390 and s390x use the "32-bit" version of this structure */
#define _KLIBC_STATFS_F_TYPE_64 0

/* So that we can avoid stack trampolines */
#define _KLIBC_NEEDS_SA_RESTORER 1
/* Our restorer will call rt_sigreturn() */
#define _KLIBC_NEEDS_SA_SIGINFO 1

#endif				/* _KLIBC_ARCHCONFIG_H */
