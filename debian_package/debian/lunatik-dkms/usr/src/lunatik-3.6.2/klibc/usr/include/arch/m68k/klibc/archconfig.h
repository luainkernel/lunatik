/*
 * include/arch/m68k/klibc/archconfig.h
 *
 * See include/klibc/sysconfig.h for the options that can be set in
 * this file.
 *
 */

#ifndef _KLIBC_ARCHCONFIG_H
#define _KLIBC_ARCHCONFIG_H

/* On m68k, sys_mmap2 uses the current page size as the shift factor */
#define _KLIBC_MMAP2_SHIFT	__getpageshift()

#endif				/* _KLIBC_ARCHCONFIG_H */
