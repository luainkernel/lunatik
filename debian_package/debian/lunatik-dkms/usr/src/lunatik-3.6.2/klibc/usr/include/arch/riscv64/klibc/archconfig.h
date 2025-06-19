/*
 * include/arch/riscv64/klibc/archconfig.h
 *
 * See include/klibc/sysconfig.h for the options that can be set in
 * this file.
 *
 */

#ifndef _KLIBC_ARCHCONFIG_H
#define _KLIBC_ARCHCONFIG_H

/* We have an MMU but no fork() syscall */
#define _KLIBC_NO_MMU 0

#endif				/* _KLIBC_ARCHCONFIG_H */
