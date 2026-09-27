# execguard

[execguard](guard.lua) is an allowlist for `exec` over one directory: a permission event
parks the `execve` inside the callback, which refuses it unless the entry's name is in the `set` it was
built with.

A second list names who may run them: when the scope holds a file `pids` as the script starts, one pid per
line, the exec is refused to every pid it does not name. That pid is the one of the thread calling `execve`,
which after a `fork` is the child's: a shell the list names runs a program there only with `exec`, which
keeps its pid. Each refusal is logged with its reason, `not in the allowlist` or `pid not allowed`.

The mark is an inode mark on `SCOPE` carrying `EVENT_ON_CHILD`, so the only exec it can refuse is of an
entry directly inside that directory. It is never a system wide default deny: a `"mount"` or `"sb"` mark
reaches every file of a mount or of a whole filesystem, and a rule that denies there leaves the machine
unable to run the programs that would undo it. Give it a scratch mount of its own, as below, so that the
`umount` ends the rule even if the script cannot be stopped.

An exec opens more than the program for exec. Inside `execve` the kernel opens a script's interpreter, the
path on its `#!` line, and an ELF program's loader, the one absolute path `ldd` prints without `=>`, the
same way, and each asks the rule under its own name: a script whose interpreter lives in the scope is
refused unless that name is in the allowlist too. `strace -e openat` shows none of those opens; what it
shows, the loader reading its cache and the libraries and an interpreter reading its script, are reads that
never reach the rule. Landlock asks for its execute right at the same opens, so the programs, their loaders
and their interpreters are the list a Landlock ruleset grants it on as well. That is also why the rule stays
on a directory of its own: on the one holding `sh` or the loader, every script or every dynamically linked
program on the machine would have to pass the allowlist.

`EVENT_ON_CHILD` reaches the entry through its parent in the directory cache, so a program opened by handle
with `open_by_handle_at` after the cache dropped its entry, and run with `execveat` and `AT_EMPTY_PATH`, is
never asked about. That takes `CAP_DAC_READ_SEARCH`, and a filesystem that drops entries: the tmpfs below
keeps every entry it holds in the cache.

On a kernel built without `CONFIG_FANOTIFY_ACCESS_PERMISSIONS`, which has no permission events, the script
still loads: it says so in the log and guards nothing.

## Usage

```
sudo make examples_install                  # installs examples
sudo mkdir -p -m 0755 /tmp/lunatik-execguard
sudo mount -t tmpfs -o size=1M,mode=0755 lunatik-execguard /tmp/lunatik-execguard
sudo cp /bin/true /bin/date /tmp/lunatik-execguard/
sudo lunatik run examples/execguard/guard   # runs execguard
/tmp/lunatik-execguard/true                 # "true" is in the allowlist: it runs
/tmp/lunatik-execguard/date                 # "date" is not
bash: /tmp/lunatik-execguard/date: Operation not permitted
sudo lunatik stop examples/execguard/guard  # ends the rule
sudo umount /tmp/lunatik-execguard          # and takes the mark with it
sudo dmesg -t                               # prints what it refused
execguard: denied date to pid 2222403: not in the allowlist
```

With a pid list:

```
sudo mount -t tmpfs -o size=1M,mode=0755 lunatik-execguard /tmp/lunatik-execguard
sudo cp /bin/true /tmp/lunatik-execguard/
bash                                        # a shell for the list to name
echo $$ | sudo tee /tmp/lunatik-execguard/pids
sudo lunatik run examples/execguard/guard   # reads the list as it starts
/tmp/lunatik-execguard/true                 # the child the shell forks has a pid of its own
bash: /tmp/lunatik-execguard/true: Operation not permitted
exec /tmp/lunatik-execguard/true            # runs in the listed pid, and ends that shell
sudo lunatik stop examples/execguard/guard
sudo umount /tmp/lunatik-execguard
sudo dmesg -t
execguard: denied true to pid 2222510: pid not allowed
```

