/*
 * include/arch/alpha/klibc/archconfig.h
 *
 * See include/klibc/sysconfig.h for the options that can be set in
 * this file.
 *
 */

#ifndef _KLIBC_ARCHCONFIG_H
#define _KLIBC_ARCHCONFIG_H

/* We provide our own restorer that call rt_sigreturn() */
#define _KLIBC_NEEDS_SA_SIGINFO 1
#define _KLIBC_STATFS_F_TYPE_64 0

#endif				/* _KLIBC_ARCHCONFIG_H */
