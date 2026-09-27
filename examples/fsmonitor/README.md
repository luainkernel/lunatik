# fsmonitor

[fsmonitor](monitor.lua) uses the `fsnotify` module to log what changes in one directory: an
entry created or deleted, a file written or its attributes changed, each line carrying the entry name,
its inode number and the pid that did it.

The mark is an inode mark on the directory `WATCHED` names, carrying `EVENT_ON_CHILD` so that events on
the files inside it are reported too. That flag is one level deep: nothing under a subdirectory arrives.
It also reaches a file only through its parent in the directory cache, so a write to a file opened by handle
with `open_by_handle_at` after the cache dropped its entry, or a change to its attributes, is not reported.

## Usage

```
sudo make install                          # installs Lunatik and the examples
mkdir -p /tmp/lunatik-fsmonitor             # the directory it watches
sudo lunatik run examples/fsmonitor/monitor # runs fsmonitor
touch /tmp/lunatik-fsmonitor/file
echo data > /tmp/lunatik-fsmonitor/file
rm /tmp/lunatik-fsmonitor/file
sudo lunatik stop examples/fsmonitor/monitor # stops fsmonitor
sudo dmesg -t                               # prints what it logged
fsmonitor: created file ino 13862 pid 2222346
fsmonitor: attributes file ino 13862 pid 2222346
fsmonitor: modified file ino 13862 pid 2222341
fsmonitor: modified file ino 13862 pid 2222341
fsmonitor: deleted file ino 13862 pid 2222347
```

The shell's redirection truncates the file on open and then writes it, so one command logs two
modifications; an event on the directory itself, its own `chmod` or `touch`, carries no entry name and
prints `?`.

