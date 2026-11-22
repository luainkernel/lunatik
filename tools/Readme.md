# Additional tools

The tools Lunatik shares with luaebpf are the harness's, under `harness/tools/`, which
`harness/tools/Readme.md` describes.

## bench/

Measures refs of Lunatik on this host, as `doc/design/benchmark/plan.md` describes: each ref is built
in a worktree under the work directory, installed in place of what is installed, measured by each
set named, and removed, and the tree the driver lives in is installed and loaded again however the
run ends, as long as its terminal lasts: sudo keys its ticket to the terminal, so a run that may
outlive one goes in tmux or screen. The rounds rotate the order of the refs. A set is
`tools/bench/<set>.sh`; the scripts it runs are installed under `/lib/modules/lua/bench/` with the
table of names of the ref's API generation, `tools/bench/names/<tag>.lua`, the tag `git describe`
gives the ref.

```sh
bash harness/tools/lunatik-host bash tools/bench/bench.sh scratch/bench 3 footprint v4.4.1 v5.0 v5.1
```

Each round writes `round<n>.csv`, one row per sample, and the run ends with `summary.csv`, the median
and the interquartile range per ref, set, operation and context. The `footprint` set reads `size` of each module
installed, the Lua heap of a runtime in each context after a full collection, and the kmalloc memory
of an empty runtime in each context, 64 of them held against none. A ref is not built below 1024 MB
free under the work directory.

## debian_kernel_postinst_lunatik.sh

Under Debian, copy this script into /etc/kernel/postinst.d/
to have Lunatik installed on kernel upgrade:

```sh
sudo cp debian_kernel_postinst_lunatik.sh /etc/kernel/postinst.d/zz-update-lunatik
sudo chmod +x /etc/kernel/postinst.d/zz-update-lunatik
```

To check it works:

```sh
sudo dpkg-reconfigure linux-image-`uname -r`
```

