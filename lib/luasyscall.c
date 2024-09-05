/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kprobes.h>

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>

static unsigned long **luasyscall_table;

static int luasyscall_address(lua_State *L)
{
	lua_Integer nr = luaL_checkinteger(L, 1);
	luaL_argcheck(L, nr >= 0 && nr < __NR_syscalls, 1, "out of bounds");
	lua_pushlightuserdata(L, (void *)luasyscall_table[nr]);
	return 1;
}

static const lunatik_reg_t luasyscall_numbers[] = {
	{"io_setup", __NR_io_setup},
	{"io_destroy", __NR_io_destroy},
	{"io_submit", __NR_io_submit},
	{"io_cancel", __NR_io_cancel},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"io_getevents", __NR_io_getevents},
#endif
	{"setxattr", __NR_setxattr},
	{"lsetxattr", __NR_lsetxattr},
	{"fsetxattr", __NR_fsetxattr},
	{"getxattr", __NR_getxattr},
	{"lgetxattr", __NR_lgetxattr},
	{"fgetxattr", __NR_fgetxattr},
	{"listxattr", __NR_listxattr},
	{"llistxattr", __NR_llistxattr},
	{"flistxattr", __NR_flistxattr},
	{"removexattr", __NR_removexattr},
	{"lremovexattr", __NR_lremovexattr},
	{"fremovexattr", __NR_fremovexattr},
	{"getcwd", __NR_getcwd},
	{"lookup_dcookie", __NR_lookup_dcookie},
	{"eventfd2", __NR_eventfd2},
	{"epoll_create1", __NR_epoll_create1},
	{"epoll_ctl", __NR_epoll_ctl},
	{"epoll_pwait", __NR_epoll_pwait},
	{"dup", __NR_dup},
	{"dup3", __NR_dup3},
	{"inotify_init1", __NR_inotify_init1},
	{"inotify_add_watch", __NR_inotify_add_watch},
	{"inotify_rm_watch", __NR_inotify_rm_watch},
	{"ioctl", __NR_ioctl},
	{"ioprio_set", __NR_ioprio_set},
	{"ioprio_get", __NR_ioprio_get},
	{"flock", __NR_flock},
	{"mknodat", __NR_mknodat},
	{"mkdirat", __NR_mkdirat},
	{"unlinkat", __NR_unlinkat},
	{"symlinkat", __NR_symlinkat},
	{"linkat", __NR_linkat},
#ifdef __ARCH_WANT_RENAMEAT
	{"renameat", __NR_renameat},
#endif
	{"umount2", __NR_umount2},
	{"mount", __NR_mount},
	{"pivot_root", __NR_pivot_root},
	{"nfsservctl", __NR_nfsservctl},
	{"fallocate", __NR_fallocate},
	{"faccessat", __NR_faccessat},
	{"chdir", __NR_chdir},
	{"fchdir", __NR_fchdir},
	{"chroot", __NR_chroot},
	{"fchmod", __NR_fchmod},
	{"fchmodat", __NR_fchmodat},
	{"fchownat", __NR_fchownat},
	{"fchown", __NR_fchown},
	{"openat", __NR_openat},
	{"close", __NR_close},
	{"vhangup", __NR_vhangup},
	{"pipe2", __NR_pipe2},
	{"quotactl", __NR_quotactl},
	{"getdents64", __NR_getdents64},
	{"read", __NR_read},
	{"write", __NR_write},
	{"readv", __NR_readv},
	{"writev", __NR_writev},
	{"pread64", __NR_pread64},
	{"pwrite64", __NR_pwrite64},
	{"preadv", __NR_preadv},
	{"pwritev", __NR_pwritev},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"pselect6", __NR_pselect6},
	{"ppoll", __NR_ppoll},
#endif
	{"signalfd4", __NR_signalfd4},
	{"vmsplice", __NR_vmsplice},
	{"splice", __NR_splice},
	{"tee", __NR_tee},
	{"readlinkat", __NR_readlinkat},
	{"sync", __NR_sync},
	{"fsync", __NR_fsync},
	{"fdatasync", __NR_fdatasync},
#ifdef __ARCH_WANT_SYNC_FILE_RANGE2
	{"sync_file_range2", __NR_sync_file_range2},
#else
	{"sync_file_range", __NR_sync_file_range},
#endif
	{"timerfd_create", __NR_timerfd_create},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"timerfd_settime", __NR_timerfd_settime},
	{"timerfd_gettime", __NR_timerfd_gettime},
#endif
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"utimensat", __NR_utimensat},
#endif
	{"acct", __NR_acct},
	{"capget", __NR_capget},
	{"capset", __NR_capset},
	{"personality", __NR_personality},
	{"exit", __NR_exit},
	{"exit_group", __NR_exit_group},
	{"waitid", __NR_waitid},
	{"set_tid_address", __NR_set_tid_address},
	{"unshare", __NR_unshare},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"futex", __NR_futex},
#endif
	{"set_robust_list", __NR_set_robust_list},
	{"get_robust_list", __NR_get_robust_list},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"nanosleep", __NR_nanosleep},
#endif
	{"getitimer", __NR_getitimer},
	{"setitimer", __NR_setitimer},
	{"kexec_load", __NR_kexec_load},
	{"init_module", __NR_init_module},
	{"delete_module", __NR_delete_module},
	{"timer_create", __NR_timer_create},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"timer_gettime", __NR_timer_gettime},
#endif
	{"timer_getoverrun", __NR_timer_getoverrun},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"timer_settime", __NR_timer_settime},
#endif
	{"timer_delete", __NR_timer_delete},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"clock_settime", __NR_clock_settime},
	{"clock_gettime", __NR_clock_gettime},
	{"clock_getres", __NR_clock_getres},
	{"clock_nanosleep", __NR_clock_nanosleep},
#endif
	{"syslog", __NR_syslog},
	{"ptrace", __NR_ptrace},
	{"sched_setparam", __NR_sched_setparam},
	{"sched_setscheduler", __NR_sched_setscheduler},
	{"sched_getscheduler", __NR_sched_getscheduler},
	{"sched_getparam", __NR_sched_getparam},
	{"sched_setaffinity", __NR_sched_setaffinity},
	{"sched_getaffinity", __NR_sched_getaffinity},
	{"sched_yield", __NR_sched_yield},
	{"sched_get_priority_max", __NR_sched_get_priority_max},
	{"sched_get_priority_min", __NR_sched_get_priority_min},
	{"sched_rr_get_interval", __NR_sched_rr_get_interval},
	{"restart_syscall", __NR_restart_syscall},
	{"kill", __NR_kill},
	{"tkill", __NR_tkill},
	{"tgkill", __NR_tgkill},
	{"sigaltstack", __NR_sigaltstack},
	{"rt_sigsuspend", __NR_rt_sigsuspend},
	{"rt_sigaction", __NR_rt_sigaction},
	{"rt_sigprocmask", __NR_rt_sigprocmask},
	{"rt_sigpending", __NR_rt_sigpending},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"rt_sigtimedwait", __NR_rt_sigtimedwait},
#endif
	{"rt_sigqueueinfo", __NR_rt_sigqueueinfo},
	{"rt_sigreturn", __NR_rt_sigreturn},
	{"setpriority", __NR_setpriority},
	{"getpriority", __NR_getpriority},
	{"reboot", __NR_reboot},
	{"setregid", __NR_setregid},
	{"setgid", __NR_setgid},
	{"setreuid", __NR_setreuid},
	{"setuid", __NR_setuid},
	{"setresuid", __NR_setresuid},
	{"getresuid", __NR_getresuid},
	{"setresgid", __NR_setresgid},
	{"getresgid", __NR_getresgid},
	{"setfsuid", __NR_setfsuid},
	{"setfsgid", __NR_setfsgid},
	{"times", __NR_times},
	{"setpgid", __NR_setpgid},
	{"getpgid", __NR_getpgid},
	{"getsid", __NR_getsid},
	{"setsid", __NR_setsid},
	{"getgroups", __NR_getgroups},
	{"setgroups", __NR_setgroups},
	{"uname", __NR_uname},
	{"sethostname", __NR_sethostname},
	{"setdomainname", __NR_setdomainname},
#ifdef __ARCH_WANT_SET_GET_RLIMIT
	{"getrlimit", __NR_getrlimit},
	{"setrlimit", __NR_setrlimit},
#endif
	{"getrusage", __NR_getrusage},
	{"umask", __NR_umask},
	{"prctl", __NR_prctl},
	{"getcpu", __NR_getcpu},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"gettimeofday", __NR_gettimeofday},
	{"settimeofday", __NR_settimeofday},
	{"adjtimex", __NR_adjtimex},
#endif
	{"getpid", __NR_getpid},
	{"getppid", __NR_getppid},
	{"getuid", __NR_getuid},
	{"geteuid", __NR_geteuid},
	{"getgid", __NR_getgid},
	{"getegid", __NR_getegid},
	{"gettid", __NR_gettid},
	{"sysinfo", __NR_sysinfo},
	{"mq_open", __NR_mq_open},
	{"mq_unlink", __NR_mq_unlink},
	{"mq_timedsend", __NR_mq_timedsend},
	{"mq_timedreceive", __NR_mq_timedreceive},
	{"mq_notify", __NR_mq_notify},
	{"mq_getsetattr", __NR_mq_getsetattr},
	{"msgget", __NR_msgget},
	{"msgctl", __NR_msgctl},
	{"msgrcv", __NR_msgrcv},
	{"msgsnd", __NR_msgsnd},
	{"semget", __NR_semget},
	{"semctl", __NR_semctl},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"semtimedop", __NR_semtimedop},
#endif
	{"semop", __NR_semop},
	{"shmget", __NR_shmget},
	{"shmctl", __NR_shmctl},
	{"shmat", __NR_shmat},
	{"shmdt", __NR_shmdt},
	{"socket", __NR_socket},
	{"socketpair", __NR_socketpair},
	{"bind", __NR_bind},
	{"listen", __NR_listen},
	{"accept", __NR_accept},
	{"connect", __NR_connect},
	{"getsockname", __NR_getsockname},
	{"getpeername", __NR_getpeername},
	{"sendto", __NR_sendto},
	{"recvfrom", __NR_recvfrom},
	{"setsockopt", __NR_setsockopt},
	{"getsockopt", __NR_getsockopt},
	{"shutdown", __NR_shutdown},
	{"sendmsg", __NR_sendmsg},
	{"recvmsg", __NR_recvmsg},
	{"readahead", __NR_readahead},
	{"brk", __NR_brk},
	{"munmap", __NR_munmap},
	{"mremap", __NR_mremap},
	{"add_key", __NR_add_key},
	{"request_key", __NR_request_key},
	{"keyctl", __NR_keyctl},
	{"clone", __NR_clone},
	{"execve", __NR_execve},
#ifndef __ARCH_NOMMU
	{"swapon", __NR_swapon},
	{"swapoff", __NR_swapoff},
	{"mprotect", __NR_mprotect},
	{"msync", __NR_msync},
	{"mlock", __NR_mlock},
	{"munlock", __NR_munlock},
	{"mlockall", __NR_mlockall},
	{"munlockall", __NR_munlockall},
	{"mincore", __NR_mincore},
	{"madvise", __NR_madvise},
	{"remap_file_pages", __NR_remap_file_pages},
	{"mbind", __NR_mbind},
	{"get_mempolicy", __NR_get_mempolicy},
	{"set_mempolicy", __NR_set_mempolicy},
	{"migrate_pages", __NR_migrate_pages},
	{"move_pages", __NR_move_pages},
#endif
	{"rt_tgsigqueueinfo", __NR_rt_tgsigqueueinfo},
	{"perf_event_open", __NR_perf_event_open},
	{"accept4", __NR_accept4},
	{"recvmmsg", __NR_recvmmsg},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"wait4", __NR_wait4},
#endif
	{"prlimit64", __NR_prlimit64},
	{"fanotify_init", __NR_fanotify_init},
	{"fanotify_mark", __NR_fanotify_mark},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"clock_adjtime", __NR_clock_adjtime},
#endif
	{"syncfs", __NR_syncfs},
	{"setns", __NR_setns},
	{"sendmmsg", __NR_sendmmsg},
	{"process_vm_readv", __NR_process_vm_readv},
	{"process_vm_writev", __NR_process_vm_writev},
	{"kcmp", __NR_kcmp},
	{"finit_module", __NR_finit_module},
	{"sched_setattr", __NR_sched_setattr},
	{"sched_getattr", __NR_sched_getattr},
	{"renameat2", __NR_renameat2},
	{"seccomp", __NR_seccomp},
	{"getrandom", __NR_getrandom},
	{"memfd_create", __NR_memfd_create},
	{"bpf", __NR_bpf},
	{"execveat", __NR_execveat},
	{"userfaultfd", __NR_userfaultfd},
	{"membarrier", __NR_membarrier},
	{"mlock2", __NR_mlock2},
	{"copy_file_range", __NR_copy_file_range},
	{"preadv2", __NR_preadv2},
	{"pwritev2", __NR_pwritev2},
	{"pkey_mprotect", __NR_pkey_mprotect},
	{"pkey_alloc", __NR_pkey_alloc},
	{"pkey_free", __NR_pkey_free},
	{"statx", __NR_statx},
#if defined(__ARCH_WANT_TIME32_SYSCALLS) || __BITS_PER_LONG != 32
	{"io_pgetevents", __NR_io_pgetevents},
#endif
	{"rseq", __NR_rseq},
	{"kexec_file_load", __NR_kexec_file_load},
#if defined(__SYSCALL_COMPAT) || __BITS_PER_LONG == 32
	{"clock_gettime64", __NR_clock_gettime64},
	{"clock_settime64", __NR_clock_settime64},
	{"clock_adjtime64", __NR_clock_adjtime64},
	{"clock_getres_time64", __NR_clock_getres_time64},
	{"clock_nanosleep_time64", __NR_clock_nanosleep_time64},
	{"timer_gettime64", __NR_timer_gettime64},
	{"timer_settime64", __NR_timer_settime64},
	{"timerfd_gettime64", __NR_timerfd_gettime64},
	{"timerfd_settime64", __NR_timerfd_settime64},
	{"utimensat_time64", __NR_utimensat_time64},
	{"pselect6_time64", __NR_pselect6_time64},
	{"ppoll_time64", __NR_ppoll_time64},
	{"io_pgetevents_time64", __NR_io_pgetevents_time64},
	{"recvmmsg_time64", __NR_recvmmsg_time64},
	{"mq_timedsend_time64", __NR_mq_timedsend_time64},
	{"mq_timedreceive_time64", __NR_mq_timedreceive_time64},
	{"semtimedop_time64", __NR_semtimedop_time64},
	{"rt_sigtimedwait_time64", __NR_rt_sigtimedwait_time64},
	{"futex_time64", __NR_futex_time64},
	{"sched_rr_get_interval_time64", __NR_sched_rr_get_interval_time64},
#endif
	{"pidfd_send_signal", __NR_pidfd_send_signal},
	{"io_uring_setup", __NR_io_uring_setup},
	{"io_uring_enter", __NR_io_uring_enter},
	{"io_uring_register", __NR_io_uring_register},
	{"open_tree", __NR_open_tree},
	{"move_mount", __NR_move_mount},
	{"fsopen", __NR_fsopen},
	{"fsconfig", __NR_fsconfig},
	{"fsmount", __NR_fsmount},
	{"fspick", __NR_fspick},
	{"pidfd_open", __NR_pidfd_open},
#ifdef __ARCH_WANT_SYS_CLONE3
	{"clone3", __NR_clone3},
#endif
	{"close_range", __NR_close_range},
	{"openat2", __NR_openat2},
	{"pidfd_getfd", __NR_pidfd_getfd},
	{"faccessat2", __NR_faccessat2},
	{"process_madvise", __NR_process_madvise},
	{"epoll_pwait2", __NR_epoll_pwait2},
	{"mount_setattr", __NR_mount_setattr},
	{"quotactl_fd", __NR_quotactl_fd},
	{"landlock_create_ruleset", __NR_landlock_create_ruleset},
	{"landlock_add_rule", __NR_landlock_add_rule},
	{"landlock_restrict_self", __NR_landlock_restrict_self},
#ifdef __ARCH_WANT_MEMFD_SECRET
	{"memfd_secret", __NR_memfd_secret},
#endif
	{"process_mrelease", __NR_process_mrelease},
#if __BITS_PER_LONG == 64 && !defined(__SYSCALL_COMPAT)
	{"fcntl", __NR_fcntl},
	{"statfs", __NR_statfs},
	{"fstatfs", __NR_fstatfs},
	{"truncate", __NR_truncate},
	{"ftruncate", __NR_ftruncate},
	{"lseek", __NR_lseek},
	{"sendfile", __NR_sendfile},
#if defined(__ARCH_WANT_NEW_STAT) || defined(__ARCH_WANT_STAT64)
	{"newfstatat", __NR_newfstatat},
	{"fstat", __NR_fstat},
#endif
	{"mmap", __NR_mmap},
	{"fadvise64", __NR_fadvise64},
#ifdef __NR3264_stat
	{"stat", __NR_stat},
	{"lstat", __NR_lstat},
#endif
#else
	{"fcntl64", __NR_fcntl64},
	{"statfs64", __NR_statfs64},
	{"fstatfs64", __NR_fstatfs64},
	{"truncate64", __NR_truncate64},
	{"ftruncate64", __NR_ftruncate64},
	{"llseek", __NR_llseek},
	{"sendfile64", __NR_sendfile64},
#if defined(__ARCH_WANT_NEW_STAT) || defined(__ARCH_WANT_STAT64)
	{"fstatat64", __NR_fstatat64},
	{"fstat64", __NR_fstat64},
#endif
	{"mmap2", __NR_mmap2},
	{"fadvise64_64", __NR_fadvise64_64},
#ifdef __NR3264_stat
	{"stat64", __NR_stat64},
	{"lstat64", __NR_lstat64},
#endif
#endif
	{NULL, 0}
};

static const lunatik_namespace_t luasyscall_flags[] = {
	{"numbers", luasyscall_numbers},
	{NULL, NULL}
};

static const luaL_Reg luasyscall_lib[] = {
	{"address", luasyscall_address},
	{NULL, NULL}
};

LUNATIK_NEWLIB(syscall, luasyscall_lib, NULL, luasyscall_flags);

static int __init luasyscall_init(void)
{
	if ((luasyscall_table = (unsigned long **)lunatik_lookup("sys_call_table")) == NULL)
		return -ENXIO;
	return 0;
}

static void __exit luasyscall_exit(void)
{
}

module_init(luasyscall_init);
module_exit(luasyscall_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

