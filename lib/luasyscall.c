/*
* SPDX-FileCopyrightText: (c) 2024-2025 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Accessing kernel system call information.
* This library allows retrieving the kernel address of a system call given its
* number, and provides a table of system call numbers accessible by their names (see `syscall.numbers`).
* This is particularly useful for kernel probing (see `probe`)
* or other low-level kernel interactions.
*
* @module syscall
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kprobes.h>

#include <lunatik.h>

static unsigned long **luasyscall_table;

/***
* Retrieves the kernel address of a system call.
* @function address
* @tparam integer syscall_number The system call number (e.g., `__NR_openat`).
* @treturn lightuserdata The kernel address of the system call entry point, or `nil` if the number is invalid or the address cannot be determined.
* @raise Error if `syscall_number` is out of bounds.
* @usage
*   local syscall = require("syscall")
*   local openat_addr = syscall.address(syscall.numbers.openat)
* @within syscall
*/
static int luasyscall_address(lua_State *L)
{
	lua_Integer nr = luaL_checkinteger(L, 1);
	luaL_argcheck(L, nr >= 0 && nr < __NR_syscalls, 1, "out of bounds");
	lua_pushlightuserdata(L, (void *)luasyscall_table[nr]);
	return 1;
}

/***
* Table of system call numbers.
* This table maps system call names (strings) to their corresponding kernel
* system call numbers (integers, e.g., `__NR_openat`). The availability of
* specific system calls depends on the kernel version and architecture, as detailed below.
* @table numbers
*   @tfield integer io_setup Create an asynchronous I/O context.
*   @tfield integer io_destroy Destroy an asynchronous I/O context.
*   @tfield integer io_submit Submit asynchronous I/O blocks.
*   @tfield integer io_cancel Cancel an outstanding asynchronous I/O operation.
*   @tfield integer setxattr Set an extended attribute value.
*   @tfield integer lsetxattr Set an extended attribute value of a symbolic link.
*   @tfield integer fsetxattr Set an extended attribute value of an open file.
*   @tfield integer getxattr Get an extended attribute value.
*   @tfield integer lgetxattr Get an extended attribute value of a symbolic link.
*   @tfield integer fgetxattr Get an extended attribute value of an open file.
*   @tfield integer listxattr List extended attribute names.
*   @tfield integer llistxattr List extended attribute names of a symbolic link.
*   @tfield integer flistxattr List extended attribute names of an open file.
*   @tfield integer removexattr Remove an extended attribute.
*   @tfield integer lremovexattr Remove an extended attribute of a symbolic link.
*   @tfield integer fremovexattr Remove an extended attribute of an open file.
*   @tfield integer getcwd Get current working directory.
*   @tfield integer lookup_dcookie Return a directory entry's path.
*   @tfield integer eventfd2 Create a file descriptor for event notification.
*   @tfield integer epoll_create1 Open an epoll file descriptor.
*   @tfield integer epoll_ctl Control interface for an epoll file descriptor.
*   @tfield integer epoll_pwait Wait for an I/O event on an epoll file descriptor.
*   @tfield integer dup Duplicate an old file descriptor.
*   @tfield integer dup3 Duplicate an old file descriptor to a new one with flags.
*   @tfield integer inotify_init1 Initialize an inotify instance.
*   @tfield integer inotify_add_watch Add a watch to an initialized inotify instance.
*   @tfield integer inotify_rm_watch Remove an existing watch from an inotify instance.
*   @tfield integer ioctl Control a device.
*   @tfield integer ioprio_set Set I/O scheduling class and priority.
*   @tfield integer ioprio_get Get I/O scheduling class and priority.
*   @tfield integer flock Apply or remove an advisory lock on an open file.
*   @tfield integer mknodat Create a special or ordinary file relative to a directory file descriptor.
*   @tfield integer mkdirat Create a directory relative to a directory file descriptor.
*   @tfield integer unlinkat Remove a file relative to a directory file descriptor.
*   @tfield integer symlinkat Create a symbolic link relative to a directory file descriptor.
*   @tfield integer linkat Make a new name for a file relative to a directory file descriptor.
*   @tfield integer umount2 Unmount a filesystem with flags.
*   @tfield integer mount Mount a filesystem.
*   @tfield integer pivot_root Change the root filesystem.
*   @tfield integer nfsservctl Syscall for NFS server control (obsolete).
*   @tfield integer fallocate Manipulate file space.
*   @tfield integer faccessat Check user's permissions for a file relative to a directory file descriptor.
*   @tfield integer chdir Change working directory.
*   @tfield integer fchdir Change working directory using a file descriptor.
*   @tfield integer chroot Change root directory.
*   @tfield integer fchmod Change permissions of a file given a file descriptor.
*   @tfield integer fchmodat Change permissions of a file relative to a directory file descriptor.
*   @tfield integer fchownat Change ownership of a file relative to a directory file descriptor.
*   @tfield integer fchown Change ownership of a file given a file descriptor.
*   @tfield integer openat Open or create a file relative to a directory file descriptor.
*   @tfield integer close Close a file descriptor.
*   @tfield integer vhangup Virtually hangup the current tty.
*   @tfield integer pipe2 Create a pipe with flags.
*   @tfield integer quotactl Manipulate disk quotas.
*   @tfield integer getdents64 Get directory entries.
*   @tfield integer read Read from a file descriptor.
*   @tfield integer write Write to a file descriptor.
*   @tfield integer readv Read data into multiple buffers.
*   @tfield integer writev Write data from multiple buffers.
*   @tfield integer pread64 Read from a file descriptor at a given offset.
*   @tfield integer pwrite64 Write to a file descriptor at a given offset.
*   @tfield integer preadv Read data into multiple buffers from a given offset.
*   @tfield integer pwritev Write data from multiple buffers at a given offset.
*   @tfield integer signalfd4 Create a file descriptor for accepting signals.
*   @tfield integer vmsplice Splice user pages to a pipe.
*   @tfield integer splice Splice data to/from a pipe.
*   @tfield integer tee Duplicate pipe content.
*   @tfield integer readlinkat Read value of a symbolic link relative to a directory file descriptor.
*   @tfield integer sync Commit filesystem caches to disk.
*   @tfield integer fsync Synchronize a file's in-core state with storage device.
*   @tfield integer fdatasync Synchronize a file's data in-core state with storage device.
*   @tfield integer timerfd_create Create a file descriptor for timer notifications.
*   @tfield integer acct Switch process accounting on or off.
*   @tfield integer capget Get process capabilities.
*   @tfield integer capset Set process capabilities.
*   @tfield integer personality Set the process execution domain.
*   @tfield integer exit Terminate the current process.
*   @tfield integer exit_group Terminate all threads in a process.
*   @tfield integer waitid Wait for process state changes.
*   @tfield integer set_tid_address Set pointer to thread ID.
*   @tfield integer unshare Disassociate parts of the process execution context.
*   @tfield integer set_robust_list Set the address of the robust futex list.
*   @tfield integer get_robust_list Get the address of the robust futex list.
*   @tfield integer getitimer Get value of an interval timer.
*   @tfield integer setitimer Set value of an interval timer.
*   @tfield integer kexec_load Load a new kernel for later execution.
*   @tfield integer init_module Load a kernel module.
*   @tfield integer delete_module Unload a kernel module.
*   @tfield integer timer_create Create a POSIX per-process timer.
*   @tfield integer timer_getoverrun Get POSIX per-process timer overrun count.
*   @tfield integer timer_delete Delete a POSIX per-process timer.
*   @tfield integer syslog Read and/or clear kernel message ring buffer; set console_loglevel.
*   @tfield integer ptrace Process trace.
*   @tfield integer sched_setparam Set scheduling parameters for a process.
*   @tfield integer sched_setscheduler Set scheduling policy and parameters for a process.
*   @tfield integer sched_getscheduler Get scheduling policy for a process.
*   @tfield integer sched_getparam Get scheduling parameters for a process.
*   @tfield integer sched_setaffinity Set a thread's CPU affinity mask.
*   @tfield integer sched_getaffinity Get a thread's CPU affinity mask.
*   @tfield integer sched_yield Yield the processor.
*   @tfield integer sched_get_priority_max Get maximum priority value for a scheduling policy.
*   @tfield integer sched_get_priority_min Get minimum priority value for a scheduling policy.
*   @tfield integer sched_rr_get_interval Get the SCHED_RR interval for the named process.
*   @tfield integer restart_syscall Restart a system call after a signal.
*   @tfield integer kill Send signal to a process.
*   @tfield integer tkill Send signal to a thread.
*   @tfield integer tgkill Send signal to a thread group.
*   @tfield integer sigaltstack Set and/or get signal stack context.
*   @tfield integer rt_sigsuspend Wait for a real-time signal.
*   @tfield integer rt_sigaction Examine and change a real-time signal action.
*   @tfield integer rt_sigprocmask Examine and change blocked real-time signals.
*   @tfield integer rt_sigpending Examine pending real-time signals.
*   @tfield integer rt_sigqueueinfo Queue a real-time signal and data.
*   @tfield integer rt_sigreturn Return from signal handler and cleanup stack frame.
*   @tfield integer setpriority Set program scheduling priority.
*   @tfield integer getpriority Get program scheduling priority.
*   @tfield integer reboot Reboot or enable/disable Ctrl-Alt-Del.
*   @tfield integer setregid Set real and effective group IDs.
*   @tfield integer setgid Set effective group ID.
*   @tfield integer setreuid Set real and effective user IDs.
*   @tfield integer setuid Set effective user ID.
*   @tfield integer setresuid Set real, effective and saved user IDs.
*   @tfield integer getresuid Get real, effective and saved user IDs.
*   @tfield integer setresgid Set real, effective and saved group IDs.
*   @tfield integer getresgid Get real, effective and saved group IDs.
*   @tfield integer setfsuid Set filesystem user ID.
*   @tfield integer setfsgid Set filesystem group ID.
*   @tfield integer times Get process times.
*   @tfield integer setpgid Set process group ID.
*   @tfield integer getpgid Get process group ID.
*   @tfield integer getsid Get session ID.
*   @tfield integer setsid Create a session and set the process group ID.
*   @tfield integer getgroups Get list of supplementary group IDs.
*   @tfield integer setgroups Set list of supplementary group IDs.
*   @tfield integer uname Get name and information about current kernel.
*   @tfield integer sethostname Set the system's hostname.
*   @tfield integer setdomainname Set the system's NIS/YP domain name.
*   @tfield integer getrusage Get resource usage.
*   @tfield integer umask Set file mode creation mask.
*   @tfield integer prctl Operations on a process or thread.
*   @tfield integer getcpu Determine CPU and NUMA node on which the calling thread is running.
*   @tfield integer getpid Get process ID.
*   @tfield integer getppid Get parent process ID.
*   @tfield integer getuid Get real user ID.
*   @tfield integer geteuid Get effective user ID.
*   @tfield integer getgid Get real group ID.
*   @tfield integer getegid Get effective group ID.
*   @tfield integer gettid Get thread ID.
*   @tfield integer sysinfo Get system information.
*   @tfield integer mq_open Open a POSIX message queue.
*   @tfield integer mq_unlink Unlink a POSIX message queue.
*   @tfield integer mq_timedsend Send a message to a POSIX message queue with timeout.
*   @tfield integer mq_timedreceive Receive a message from a POSIX message queue with timeout.
*   @tfield integer mq_notify Register for asynchronous notification of message arrival on a POSIX message queue.
*   @tfield integer mq_getsetattr Get/set POSIX message queue attributes.
*   @tfield integer msgget Get a System V message queue identifier.
*   @tfield integer msgctl System V message control operations.
*   @tfield integer msgrcv Receive messages from a System V message queue.
*   @tfield integer msgsnd Send a message to a System V message queue.
*   @tfield integer semget Get a System V semaphore set identifier.
*   @tfield integer semctl System V semaphore control operations.
*   @tfield integer semop System V semaphore operations.
*   @tfield integer shmget Allocates a System V shared memory segment.
*   @tfield integer shmctl System V shared memory control.
*   @tfield integer shmat Attach the System V shared memory segment to the address space of the calling process.
*   @tfield integer shmdt Detach the System V shared memory segment from the address space of the calling process.
*   @tfield integer socket Create an endpoint for communication.
*   @tfield integer socketpair Create a pair of connected sockets.
*   @tfield integer bind Bind a name to a socket.
*   @tfield integer listen Listen for connections on a socket.
*   @tfield integer accept Accept a connection on a socket.
*   @tfield integer connect Initiate a connection on a socket.
*   @tfield integer getsockname Get socket name.
*   @tfield integer getpeername Get name of connected peer socket.
*   @tfield integer sendto Send a message on a socket.
*   @tfield integer recvfrom Receive a message from a socket.
*   @tfield integer setsockopt Set options on sockets.
*   @tfield integer getsockopt Get options on sockets.
*   @tfield integer shutdown Shut down part of a full-duplex connection.
*   @tfield integer sendmsg Send a message on a socket using a message structure.
*   @tfield integer recvmsg Receive a message from a socket using a message structure.
*   @tfield integer readahead Initiate readahead on a file descriptor.
*   @tfield integer brk Change data segment size.
*   @tfield integer munmap Unmap files or devices into memory.
*   @tfield integer mremap Remap a virtual memory address.
*   @tfield integer add_key Add a key to the kernel's key management facility.
*   @tfield integer request_key Request a key from the kernel's key management facility.
*   @tfield integer keyctl Manipulate the kernel's key management facility.
*   @tfield integer clone Create a child process.
*   @tfield integer execve Execute a program.
*   @tfield integer rt_tgsigqueueinfo Send a real-time signal with data to a thread group.
*   @tfield integer perf_event_open Set up performance monitoring.
*   @tfield integer accept4 Accept a connection on a socket with flags.
*   @tfield integer recvmmsg Receive multiple messages from a socket.
*   @tfield integer prlimit64 Get and set resource limits.
*   @tfield integer fanotify_init Create and initialize fanotify group.
*   @tfield integer fanotify_mark Add, remove, or modify an fanotify mark on a filesystem object.
*   @tfield integer syncfs Commit filesystem caches to disk for a specific filesystem.
*   @tfield integer setns Reassociate thread with a namespace.
*   @tfield integer sendmmsg Send multiple messages on a socket.
*   @tfield integer process_vm_readv Read from another process's memory.
*   @tfield integer process_vm_writev Write to another process's memory.
*   @tfield integer kcmp Compare two processes to determine if they share a kernel resource.
*   @tfield integer finit_module Load a kernel module from a file descriptor.
*   @tfield integer sched_setattr Set scheduling policy and attributes for a thread.
*   @tfield integer sched_getattr Get scheduling policy and attributes for a thread.
*   @tfield integer renameat2 Rename a file or directory, with flags.
*   @tfield integer seccomp Operate on Secure Computing state of the process.
*   @tfield integer getrandom Obtain a series of random bytes.
*   @tfield integer memfd_create Create an anonymous file.
*   @tfield integer bpf Perform a BPF operation.
*   @tfield integer execveat Execute a program relative to a directory file descriptor.
*   @tfield integer userfaultfd Create a file descriptor for handling page faults in user space.
*   @tfield integer membarrier Issue memory barriers.
*   @tfield integer mlock2 Lock memory with flags.
*   @tfield integer copy_file_range Copy a range of data from one file to another.
*   @tfield integer preadv2 Read data into multiple buffers from a given offset, with flags.
*   @tfield integer pwritev2 Write data from multiple buffers at a given offset, with flags.
*   @tfield integer pkey_mprotect Set protection on a region of memory, with a protection key.
*   @tfield integer pkey_alloc Allocate a protection key.
*   @tfield integer pkey_free Free a protection key.
*   @tfield integer statx Get file status (extended).
*   @tfield integer rseq Restartable sequences.
*   @tfield integer kexec_file_load Load a new kernel for later execution from a file descriptor.
*   @tfield integer pidfd_send_signal Send a signal to a process specified by a PID file descriptor.
*   @tfield integer io_uring_setup Setup an io_uring instance.
*   @tfield integer io_uring_enter Register files or submit I/O to an io_uring instance.
*   @tfield integer io_uring_register Register files or user buffers for an io_uring instance.
*   @tfield integer open_tree Open a filesystem object by path and attribute.
*   @tfield integer move_mount Move a mount.
*   @tfield integer fsopen Open a filesystem by name and flags.
*   @tfield integer fsconfig Configure a filesystem.
*   @tfield integer fsmount Mount a filesystem.
*   @tfield integer fspick Select a filesystem by fd and path.
*   @tfield integer pidfd_open Obtain a file descriptor that refers to a process.
*
*   --- Conditional on `__ARCH_WANT_TIME32_SYSCALLS` or `__BITS_PER_LONG != 32` ---
*   @tfield integer io_getevents Read asynchronous I/O events from the completion queue.
*   @tfield integer pselect6 Synchronous I/O multiplexing with a timeout and a signal mask.
*   @tfield integer ppoll Wait for some event on a file descriptor with a timeout and a signal mask.
*   @tfield integer timerfd_settime Arm or disarm a timer that notifies via a file descriptor.
*   @tfield integer timerfd_gettime Get current setting of a timer that notifies via a file descriptor.
*   @tfield integer utimensat Change file last access and modification times relative to a directory file descriptor.
*   @tfield integer futex Fast user-space locking.
*   @tfield integer nanosleep High-resolution sleep.
*   @tfield integer timer_gettime Get POSIX per-process timer.
*   @tfield integer timer_settime Arm/disarm POSIX per-process timer.
*   @tfield integer clock_settime Set time of a specified clock.
*   @tfield integer clock_gettime Get time of a specified clock.
*   @tfield integer clock_getres Get resolution of a specified clock.
*   @tfield integer clock_nanosleep High-resolution sleep with a specific clock.
*   @tfield integer rt_sigtimedwait Synchronously wait for queued real-time signals.
*   @tfield integer gettimeofday Get time.
*   @tfield integer settimeofday Set time.
*   @tfield integer adjtimex Tune kernel clock.
*   @tfield integer semtimedop System V semaphore operations with timeout.
*   @tfield integer wait4 Wait for process state changes, BSD style.
*   @tfield integer clock_adjtime Tune a specified clock.
*   @tfield integer io_pgetevents Read AIO events with timeout and signal mask.
*
*   --- Conditional on `__ARCH_WANT_RENAMEAT` ---
*   @tfield integer renameat Rename a file or directory relative to directory file descriptors.
*
*   --- Conditional on `__ARCH_WANT_SYNC_FILE_RANGE2` ---
*   @tfield integer sync_file_range2 Sync a file segment with disk, with flags.
*
*   --- Conditional on `!__ARCH_WANT_SYNC_FILE_RANGE2` (else part) ---
*   @tfield integer sync_file_range Sync a file segment with disk.
*
*   --- Conditional on `__ARCH_WANT_SET_GET_RLIMIT` ---
*   @tfield integer getrlimit Get resource limits.
*   @tfield integer setrlimit Set resource limits.
*
*   --- Conditional on `!__ARCH_NOMMU` ---
*   @tfield integer swapon Start swapping to a file or block device.
*   @tfield integer swapoff Stop swapping to a file or block device.
*   @tfield integer mprotect Set protection on a region of memory.
*   @tfield integer msync Synchronize a file with a memory map.
*   @tfield integer mlock Lock memory.
*   @tfield integer munlock Unlock memory.
*   @tfield integer mlockall Lock all pages mapped into the address space of the calling process.
*   @tfield integer munlockall Unlock all pages mapped into the address space of the calling process.
*   @tfield integer mincore Determine whether pages are resident in memory.
*   @tfield integer madvise Give advice about use of memory.
*   @tfield integer remap_file_pages Create a nonlinear file mapping.
*   @tfield integer mbind Set memory policy for a memory range.
*   @tfield integer get_mempolicy Retrieve NUMA memory policy for a thread.
*   @tfield integer set_mempolicy Set NUMA memory policy for a thread.
*   @tfield integer migrate_pages Migrate pages of the calling process to a set of nodes.
*   @tfield integer move_pages Move pages of the calling process to specific nodes.
*
*   --- Conditional on `__SYSCALL_COMPAT` or `__BITS_PER_LONG == 32` ---
*   @tfield integer clock_gettime64 Get time of a specified clock (64-bit time_t).
*   @tfield integer clock_settime64 Set time of a specified clock (64-bit time_t).
*   @tfield integer clock_adjtime64 Tune a specified clock (64-bit time_t).
*   @tfield integer clock_getres_time64 Get resolution of a specified clock (64-bit time_t).
*   @tfield integer clock_nanosleep_time64 High-resolution sleep with a specific clock (64-bit time_t).
*   @tfield integer timer_gettime64 Get POSIX per-process timer (64-bit time_t).
*   @tfield integer timer_settime64 Arm/disarm POSIX per-process timer (64-bit time_t).
*   @tfield integer timerfd_gettime64 Get current setting of a timerfd (64-bit time_t).
*   @tfield integer timerfd_settime64 Arm or disarm a timerfd (64-bit time_t).
*   @tfield integer utimensat_time64 Change file timestamps relative to a directory fd (64-bit time_t).
*   @tfield integer pselect6_time64 Synchronous I/O multiplexing (64-bit time_t).
*   @tfield integer ppoll_time64 Wait for some event on a file descriptor (64-bit time_t).
*   @tfield integer io_pgetevents_time64 Read AIO events with timeout and signal mask (64-bit time_t).
*   @tfield integer recvmmsg_time64 Receive multiple messages from a socket (64-bit time_t).
*   @tfield integer mq_timedsend_time64 Send a message to a POSIX message queue with timeout (64-bit time_t).
*   @tfield integer mq_timedreceive_time64 Receive a message from a POSIX message queue with timeout (64-bit time_t).
*   @tfield integer semtimedop_time64 System V semaphore operations with timeout (64-bit time_t).
*   @tfield integer rt_sigtimedwait_time64 Synchronously wait for queued real-time signals (64-bit time_t).
*   @tfield integer futex_time64 Fast user-space locking (64-bit time_t).
*   @tfield integer sched_rr_get_interval_time64 Get the SCHED_RR interval for the named process (64-bit time_t).
*
*   --- Conditional on `__ARCH_WANT_SYS_CLONE3` ---
*   @tfield integer clone3 Create a child process with a new API.
*
*   --- Conditional on `LINUX_VERSION_CODE >= KERNEL_VERSION(5, 9, 0)` ---
*   @tfield integer close_range Close a range of file descriptors.
*
*   --- Conditional on `LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)` ---
*   @tfield integer openat2 Open or create a file relative to a directory file descriptor, with extended flags.
*   @tfield integer pidfd_getfd Obtain a duplicate of another process's file descriptor.
*
*   --- Conditional on `LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0)` ---
*   @tfield integer faccessat2 Check user's permissions for a file relative to a directory fd, with flags.
*
*   --- Conditional on `LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)` ---
*   @tfield integer process_madvise Give advice about use of memory to a process.
*
*   --- Conditional on `LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)` ---
*   @tfield integer epoll_pwait2 Wait for an I/O event on an epoll file descriptor, with extended timeout.
*
*   --- Conditional on `LINUX_VERSION_CODE >= KERNEL_VERSION(5, 12, 0)` ---
*   @tfield integer mount_setattr Change properties of a mount.
*
*   --- Conditional on `LINUX_VERSION_CODE >= KERNEL_VERSION(5, 14, 0)` ---
*   @tfield integer quotactl_fd Manipulate disk quotas using a file descriptor.
*
*   --- Conditional on `LINUX_VERSION_CODE >= KERNEL_VERSION(5, 13, 0)` ---
*   @tfield integer landlock_create_ruleset Create a new Landlock ruleset.
*   @tfield integer landlock_add_rule Add a new rule to a Landlock ruleset.
*   @tfield integer landlock_restrict_self Enforce a Landlock ruleset on the calling thread.
*
*   --- Conditional on `__ARCH_WANT_MEMFD_SECRET` ---
*   @tfield integer memfd_secret Create an anonymous file in RAM for secrets.
*
*   --- Conditional on `LINUX_VERSION_CODE >= KERNEL_VERSION(5, 15, 0)` ---
*   @tfield integer process_mrelease Release memory of a remote process.
*
*   --- Conditional on `__BITS_PER_LONG == 64` and `!__SYSCALL_COMPAT` ---
*   @tfield integer fcntl Manipulate file descriptor.
*   @tfield integer statfs Get filesystem statistics.
*   @tfield integer fstatfs Get filesystem statistics for an open file.
*   @tfield integer truncate Truncate a file to a specified length.
*   @tfield integer ftruncate Truncate an open file to a specified length.
*   @tfield integer lseek Reposition read/write file offset.
*   @tfield integer sendfile Transfer data between file descriptors.
*   @tfield integer newfstatat Get file status relative to a directory fd (new stat struct).
*   @tfield integer fstat Get file status for an open file (new stat struct).
*   @tfield integer mmap Map files or devices into memory.
*   @tfield integer fadvise64 Predeclare an access pattern for file data.
*   @tfield integer stat Get file status.
*   @tfield integer lstat Get symbolic link status.
*
*   --- Conditional on `__BITS_PER_LONG != 64` or `__SYSCALL_COMPAT` (else part of above) ---
*   @tfield integer fcntl64 Manipulate file descriptor (64-bit version).
*   @tfield integer statfs64 Get filesystem statistics (64-bit version).
*   @tfield integer fstatfs64 Get filesystem statistics for an open file (64-bit version).
*   @tfield integer truncate64 Truncate a file to a specified length (64-bit version).
*   @tfield integer ftruncate64 Truncate an open file to a specified length (64-bit version).
*   @tfield integer llseek Reposition read/write file offset (long long version).
*   @tfield integer sendfile64 Transfer data between file descriptors (64-bit version).
*   @tfield integer fstatat64 Get file status relative to a directory fd (64-bit stat struct).
*   @tfield integer fstat64 Get file status for an open file (64-bit stat struct).
*   @tfield integer mmap2 Map files or devices into memory (with offset in pages).
*   @tfield integer fadvise64_64 Predeclare an access pattern for file data (64-bit offset/len).
*   @tfield integer stat64 Get file status (64-bit stat struct).
*   @tfield integer lstat64 Get symbolic link status (64-bit stat struct).
* @within syscall
*/
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
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 9, 0)
	{"close_range", __NR_close_range},
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)
	{"openat2", __NR_openat2},
	{"pidfd_getfd", __NR_pidfd_getfd},
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 8, 0)
	{"faccessat2", __NR_faccessat2},
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)
	{"process_madvise", __NR_process_madvise},
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)
	{"epoll_pwait2", __NR_epoll_pwait2},
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 12, 0)
	{"mount_setattr", __NR_mount_setattr},
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 14, 0)
	{"quotactl_fd", __NR_quotactl_fd},
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 13, 0)
	{"landlock_create_ruleset", __NR_landlock_create_ruleset},
	{"landlock_add_rule", __NR_landlock_add_rule},
	{"landlock_restrict_self", __NR_landlock_restrict_self},
#endif
#ifdef __ARCH_WANT_MEMFD_SECRET
	{"memfd_secret", __NR_memfd_secret},
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 15, 0)
	{"process_mrelease", __NR_process_mrelease},
#endif
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

