/*
 *
 * Architecture-specific signal definitions
 *
 */

#ifndef _KLIBC_ARCHSIGNAL_H
#define _KLIBC_ARCHSIGNAL_H

#define __WANT_POSIX1B_SIGNALS__

#include <linux/signal.h>

/* Not actually used by the kernel... */
#define SA_RESTORER	0x80000000

#endif
