/*
 * sys/reboot.h
 */

#ifndef _SYS_REBOOT_H
#define _SYS_REBOOT_H

#include <klibc/extern.h>
#include <linux/reboot.h>

/* glibc names these constants differently; allow both versions */

#define RB_AUTOBOOT	LINUX_REBOOT_CMD_RESTART
#define RB_HALT_SYSTEM	LINUX_REBOOT_CMD_HALT
#define RB_ENABLE_CAD	LINUX_REBOOT_CMD_CAD_ON
#define RB_DISABLE_CAD	LINUX_REBOOT_CMD_CAD_OFF
#define RB_POWER_OFF	LINUX_REBOOT_CMD_POWER_OFF

/* two-arguments version of reboot */
__extern int reboot(int, void *);

/* Native four-argument system call */
__extern int __reboot(int, int, int, void *);

#endif				/* _SYS_REBOOT_H */
