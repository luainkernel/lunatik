/*
 * include/arch/x86_64/klibc/archconfig.h
 *
 * See include/klibc/sysconfig.h for the options that can be set in
 * this file.
 *
 */

#ifndef _KLIBC_ARCHCONFIG_H
#define _KLIBC_ARCHCONFIG_H

/* x86-64 doesn't provide a default sigreturn. */
#define _KLIBC_NEEDS_SA_RESTORER 1

#endif				/* _KLIBC_ARCHCONFIG_H */
