# The set image format

`set.image.load(path, maxbytes)` builds a `set` from a file a tool writes in userspace: it reads the
file with `data.load` and builds the set over its bytes with `set.fromdata(d, layout)`. This note records
why the file is the set's own layout behind a 16-byte header, why the header is read in Lua and the
file and the set are a `data` and a binding over it, and what else was weighed. The layout and its
rules, as a script author and a writer need them, are in the `set.image` module's documentation.

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

The size is exactly `16 + 4(n+1) + 4n·labeled + len`. `set.image` checks the magic, the version, the
flags and the size, and hands `set.fromdata` the layout of the arrays behind the header. `set.fromdata`
checks once that every array fits in the data at a multiple of 4, and `has` and `match` run the same
binary search `set.new(t)`'s sets run, over the buffer the file was read into, reading a member only
when its offsets keep it inside the bytes from `blob` on. The members of a file without labels answer
1, as a list's do.

That is the whole check of the content. Members out of order or repeated, offsets that decrease or
reach past the data and a label of 0 make the lookups answer wrong and read nothing outside the data,
so they are the error of whoever wrote the file, as a wrong member in a Lua table is; the writer,
`tests/set/write.lua`, sorts and checks what it writes.

The byte order is fixed, so a file moves between hosts: on a big-endian CPU the set converts each
offset and label as it reads it and writes nothing into the data, and on a little-endian one that is
no work. A later layout takes a new version, and `set.image` refuses every version but the one it
reads, as it refuses a flag it does not know, the way BTF refuses both.

## What was weighed

**A text list parsed in the kernel.** The smallest change: no format, any tool's list loads as it
is. The text, a 16-byte index entry per member for the sort, and the set itself coexist, about three
times the set; the kernel sorts and parses at every load; and a file carries no version, so a later
change to the line grammar is told apart by nothing, and a wrong file parses into a wrong set.

**The set's own layout behind a header**, the choice. What `data.load` reads the file into is the set:
nothing is copied, sorted or indexed in the kernel, so the peak is the file, the set plus 16 bytes.
The lookup code is the one `set.new(t)` already runs. This is how the kernel loads its own compiled
tables: cfg80211's `regulatory.db`, BTF and AppArmor's DFA are compiled in userspace, loaded whole,
checked once up front and trusted on the hot path. The set checks its arrays once and each member
where a lookup reads it, two comparisons a probe in place of a pass over every offset at load, so an
offset its writer got wrong answers wrong, as a member out of order does, and is not a refusal of its
own. It costs a format Lunatik owns, documented where a writer reads it; the suite's own writer,
`tests/set/write.lua`, is
the one the tree carries, so no verb of the CLI takes it on.

**cdb**, D. J. Bernstein's constant database: a table of 256 pointers, records of key and data
lengths, keys and data, then 256 linearly probed hash tables; 32-bit little-endian, files up to
4 GB. It buys an established specification, writers that exist, and exact lookups in `O(1)`. It
costs 28 bytes beside each key, 8 of lengths, 4 of data and 16 of hash slots, where the sorted
layout keeps 8, an offset and a label; it has no magic and no version; it has no order, so
`match`'s walk is a hash per level and `set.fromdata` would need a hash table builder or a second lookup
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
the kernel would walk the graph at load or check every access in `match`; and `set.fromdata` would need a
minimizing builder in the kernel, or a second representation.

**A finite state transducer**, as Lucene's FST or the Rust `fst` crate: compression comparable to a
DAFSA with values that hold a label. Neither documents a stable on-disk format to write a kernel
reader against, and the builder is far past what the kernel should carry.

**A builder or an iterator**, `set.new` fed one member at a time from a file the script reads: no
format and no writer, but still a Lua string per member, a growing array in C that doubles, and the
file itself as one Lua string; several times the set.

## Reading the file

`data.load(path, maxbytes)` opens the path with `filp_open`, as `kernel_read_file_from_path` does,
sizes a block of the runtime's allocator from the opened file and hands it to `kernel_read_file(file,
0, &buf, size, NULL, READING_UNKNOWN)`, `EXPORT_SYMBOL_GPL` with the same signature from 6.6 to
mainline, which refuses a non-regular or empty file with `EINVAL` and a file larger than its buffer
with `EFBIG`, denies writers while it reads, and passes the file through the security hooks every
file the kernel loads passes, LoadPin among them (fs/kernel_read_file.c:35-145). `data.load` makes
those two refusals before it allocates, as `kernel_read_file` makes them before its own `vmalloc`. The
buffer is the runtime allocator's, as `data.new`'s is, and not the `vmalloc` `kernel_read_file` makes
of any size when handed none: `lunatik_free` defers a free in atomic context by writing its item into
a block from `vmalloc`, which `lunatik_alloc` takes only past a page. `request_firmware_into_buf`
hands `kernel_read_file` its caller's buffer the same way (drivers/base/firmware_loader/main.c:505-506).

`request_firmware`, which cfg80211 loads `regulatory.db` through, was weighed: it takes a
`struct device`, looks only under the firmware paths, bounds the size only through
`request_firmware_into_buf` and a buffer allocated beforehand, and reads with
`kernel_read_file_from_path_initns` underneath (drivers/base/firmware_loader/main.c:549), the same
primitive one layer down. `lunatik_loadfile` streams a script into `lua_load` in page-sized chunks;
a set needs the file whole, and the kernel's call already does that.

## What is generic

Nothing in the format names a consumer: members are byte strings, labels the 32-bit integers a `set`
already carries, and the `.` walk is `match`'s. The pieces are split by what each serves.

**The read is `data`'s.** `data` is the binding for raw memory, so a file read whole is a `data`
that owns it: `regulatory.db` or BTF are read the same way and parsed in Lua with `getuint32`,
`string.unpack` and `byteorder`.

**The build is a binding over a `data`.** `set.fromdata(d, layout)` takes the arrays where the data holds
them, so a set is built from a file, from bytes a script wrote, or from any blob. A binding whose
lookup is hot builds over a data the same way, through `luadata_checkreadonly`: it refuses a view of
memory the kernel owns, an skb's or an XDP packet's, and marks the data read only for good under its
lock before it hands back the pointer and the size, so `resize`, which moves the bytes, is refused
from then on and `luadata_reset` already refuses an owned data. The binding holds the data by a
reference, as `struct btf` holds its `data` under `refcnt` (kernel/bpf/btf.c:244-255), so the bytes
outlive the script's handle and reach every runtime the object is passed to, read without a lock.
A lock per lookup, and a pin count that refuses `resize` while sets live, were weighed: each buys a
data writable again once its sets are gone, which nothing asks for, at a cost on the lookup or on the
data.

**The header is `set`'s, and Lua's.** `set.image` reads it, so a field, a version or a section the
format gains is a change to that module and not to the kernel's; the kernel keeps one header per
format too (`btf_header`, `fwdb_header`, the DFA's `table_header`), and the check that keeps every
lookup inside the data is the one the binding makes whatever wrote the bytes.

**Lua 5.5's external strings** were weighed for reading members from Lua without a copy: each still
takes a header of its own and a NUL after its bytes, so they keep the allocation they were to remove,
and the set reads the blob in C anyway.

## Kernel references (6.8)

- `fs/kernel_read_file.c:35-125`: `kernel_read_file`, `S_ISREG` and `i_size <= 0` refused with
  `-EINVAL`, `i_size > buf_size` with `-EFBIG` before `vmalloc`, which runs only for a `*buf` of
  NULL (79-80), `deny_write_access`, `security_kernel_read_file` and
  `security_kernel_post_read_file`; `kernel_read_file_from_path` at 127-145, `filp_open` and `fput`.
- `net/wireless/reg.c:648-656, 813-840`: `fwdb_header`, big-endian magic and version, and
  `valid_regdb`, which checks the size, the magic, the version and every country before use.
- `kernel/bpf/btf.c:5249-5311` and `include/uapi/linux/btf.h:8-22`: `btf_parse_hdr` checks
  `hdr_len`, the magic, the version, and refuses any flag; `struct btf` at 244-255 holds `data` and
  `data_size` under `refcnt`.
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

