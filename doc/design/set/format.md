# The set file format

`set.load(path, maxbytes)` builds a `set` from a file a tool writes in userspace. This note records why
the file is the set's own layout behind a 16-byte header, and what else was weighed. The layout and
its rules, as a script author and a writer need them, are in the `set` module's documentation,
beside `set.load`.

## The need

`set.new(t)` takes the members as a Lua table, so a script that loads a list of hundreds of
thousands of domains first builds a Lua string per member and a table of all of them: a runtime
that loaded two sets from a list of 320,718 domains peaked at 121 MB of kernel memory, for sets that
keep 12.9 MB. A file prepared in userspace should build the same set with a peak near the set's
own size, no Lua string per member, a bound the caller sets before memory is committed, and a
refusal, not an out-of-bounds read, for a file that is wrong, whoever wrote it.

## The format

Little-endian throughout, every u32 aligned to 4 bytes:

| Bytes | Field |
|-------|-------|
| 0..3 | magic, the ASCII bytes `LSET` |
| 4..5 | u16 version, 1 |
| 6..7 | u16 flags: bit 0, the file carries labels; every other bit 0 |
| 8..11 | u32 `n`, the number of members |
| 12..15 | u32 `len`, the bytes of the members |
| 16.. | u32 `off[n+1]`, member `i` spanning `off[i]` up to `off[i+1]` |
| | u32 `labels[n]`, only with bit 0 |
| | the members concatenated in `len` bytes |

The size is exactly `16 + 4(n+1) + 4n·labeled + len`. The loader checks, once and in `O(n + len)`,
that `off[0]` is 0, that no offset is below the one before it and `off[n]` is `len`, that the members
are strictly increasing in the order `luaset_keycmp` defines (bytes compared over the common prefix,
the shorter first on a tie), so sorted and unique, and that every label is in `[1, 2^32)`. After that,
`has` and `match` run the same binary search `set.new`'s sets run, over the buffer the file was
read into. The members of a file without labels answer 1, as a list's do.

The byte order is fixed, so a file moves between hosts: on a big-endian CPU the loader converts the
offsets and the labels in place before it checks them, and on a little-endian one that is no work. A
later layout takes a new version, and a build refuses every version but the one it reads, as it
refuses a flag it does not know, the way BTF refuses both.

## What was weighed

**A text list parsed in the kernel.** The smallest change: no format, any tool's list loads as it
is. The text, a 16-byte index entry per member for the sort, and the set itself coexist, about three
times the set; the kernel sorts and parses at every load; and a file carries no version, so a later
change to the line grammar is told apart by nothing, and a wrong file parses into a wrong set.

**The set's own layout behind a header**, the choice. What `kernel_read_file` allocates is the set:
nothing is copied, sorted or indexed in the kernel, so the peak is the file, the set plus 16 bytes.
The lookup code is the one `set.new` already runs. This is how the kernel loads its own compiled
tables: cfg80211's `regulatory.db`, BTF and AppArmor's DFA are compiled in userspace, loaded whole,
checked once up front and trusted on the hot path. It costs a format Lunatik owns, documented where a
writer reads it, and a check of `O(n + len)` at load; the suite's own writer, `tests/set/write.lua`, is
the one the tree carries, so no verb of the CLI takes it on.

**cdb**, D. J. Bernstein's constant database: a table of 256 pointers, records of key and data
lengths, keys and data, then 256 linearly probed hash tables; 32-bit little-endian, files up to
4 GB. It buys an established specification, writers that exist, and exact lookups in `O(1)`. It
costs 28 bytes beside each key, 8 of lengths, 4 of data and 16 of hash slots, where the sorted
layout keeps 8, an offset and a label; it has no magic and no version; it has no order, so
`match`'s walk is a hash per level and `set.new` would need a hash table builder or a second lookup
path; and a 4-byte label is still a Lunatik convention over cdb's data, so the format would not be
borrowed whole.

**A sorted string table** in LevelDB's format: prefix-compressed blocks with restart points,
varints, CRC32C, an index block and a footer with a little-endian magic. It is designed for a disk
read through a block cache. In memory the blocks, varints and checksums buy nothing over a flat
offset array, the reader would be hundreds of lines, domains share suffixes rather than prefixes so
the compression does little on them, and the footer carries no version.

**A DAFSA**, as Chromium's `make_dafsa.py` compiles the public suffix list and libpsl stores it
behind a `.DAFSA@PSL_0` line: a byte graph with suffix and prefix sharing, a few bytes per member,
lookups in `O(len)`. The value a member carries is 0 to 31 by the encoding and 0 to 7 by the
writer, so a 32-bit label makes it a format of Lunatik's own; neither reader checks the graph up
front (Chromium checks no offset against the length, libpsl checks each access against the end), so
the kernel would walk the graph at load or check every access in `match`; and `set.new` would need a
minimizing builder in the kernel, or a second representation.

**A finite state transducer**, as Lucene's FST or the Rust `fst` crate: compression comparable to a
DAFSA with values that hold a label. Neither documents a stable on-disk format to write a kernel
reader against, and the builder is far past what the kernel should carry.

**A builder or an iterator**, `set.new` fed one member at a time from a file the script reads: no
format and no writer, but still a Lua string per member, a growing array in C that doubles, and the
file itself as one Lua string; several times the set.

## Reading the file

`kernel_read_file_from_path(path, 0, &buf, maxbytes, NULL, READING_UNKNOWN)`, `EXPORT_SYMBOL_GPL`
with the same signature from 6.6 to mainline, opens the path as `filp_open` does, the way
`bpf.hash`'s `kern_path` resolves one, refuses a non-regular or empty file with `EINVAL`, refuses a
file larger than `maxbytes` with `EFBIG` before it allocates, denies writers while it reads, and
passes the file through the security hooks every file the kernel loads passes, LoadPin among them
(fs/kernel_read_file.c:35-145). The buffer is a `vmalloc` the set keeps and frees with `kvfree`.

`request_firmware`, which cfg80211 loads `regulatory.db` through, was weighed: it takes a
`struct device`, looks only under the firmware paths, bounds the size only through
`request_firmware_into_buf` and a buffer allocated beforehand, and reads with
`kernel_read_file_from_path_initns` underneath (drivers/base/firmware_loader/main.c:549), the same
primitive one layer down. `lunatik_loadfile` streams a script into `lua_load` in page-sized chunks;
a set needs the file whole, and the kernel's call already does that.

## What is generic

Nothing in the format names a consumer: members are byte strings, labels the 32-bit integers a `set`
already carries, and the `.` walk is `match`'s. Reading a file into a kernel buffer is the kernel's
primitive, one call, so it has no wrapper in the core. The header is the set's, in `lib/luaset.c`:
the kernel keeps one per format (`btf_header`, `fwdb_header`, the DFA's `table_header`), and a core
helper with one caller has nothing to mirror. When a second binding loads a binary file, the first
eight bytes, magic, version and flags, are the prefix that moves to the core, with both callers in
hand.

## Kernel references (6.8)

- `fs/kernel_read_file.c:35-125`: `kernel_read_file`, `S_ISREG` and `i_size <= 0` refused with
  `-EINVAL`, `i_size > buf_size` with `-EFBIG` before `vmalloc`, `deny_write_access`,
  `security_kernel_read_file` and `security_kernel_post_read_file`; `kernel_read_file_from_path` at
  127-145, `filp_open` and `fput`.
- `net/wireless/reg.c:648-656, 813-840`: `fwdb_header`, big-endian magic and version, and
  `valid_regdb`, which checks the size, the magic, the version and every country before use.
- `kernel/bpf/btf.c:5249-5311` and `include/uapi/linux/btf.h:8-22`: `btf_parse_hdr` checks
  `hdr_len`, the magic, the version, and refuses any flag.
- `security/apparmor/match.c:153-219`: `verify_dfa` checks every transition against the state count
  before the DFA is used, and refuses with `-EPROTO`.
- `kernel/kallsyms.c:173-227`: `kallsyms_lookup_names` bisects names sorted at build time, the
  kernel's own sorted string table.
- `mm/vmalloc.c:2825` and `mm/util.c`: `vfree` and `kvfree`, which free the buffer.

## Formats read

- cdb: <https://cr.yp.to/cdb/cdb.txt>
- LevelDB table format: <https://github.com/google/leveldb/blob/main/doc/table_format.md>
- Chromium's DAFSA: `net/tools/dafsa/make_dafsa.py` and `net/base/lookup_string_in_fixed_set.cc`
- libpsl: `src/lookup_string_in_fixed_set.c` and `src/psl.c`
- `fst`: <https://docs.rs/fst/latest/fst/>

