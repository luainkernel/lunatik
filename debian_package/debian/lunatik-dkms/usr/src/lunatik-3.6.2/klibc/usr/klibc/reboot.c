/*
 * reboot.c
 */

#include <unistd.h>
#include <sys/reboot.h>
#include <sys/syscall.h>

/* This provides two-argument reboot function (glibc flag plus reboot argument).
   The full four-argument system call is available as __reboot(). */

int reboot(int flag, void *arg)
{
	return __reboot(LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, flag, arg);
}
