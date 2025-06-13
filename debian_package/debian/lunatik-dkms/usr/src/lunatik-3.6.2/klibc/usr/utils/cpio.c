/* copyin.c - extract or list a cpio archive
   Copyright (C) 1990,1991,1992,2001,2002,2003,2004 Free Software Foundation, Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along
   with this program; if not, write to the Free Software Foundation, Inc.,
   59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.  */

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <malloc.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <utime.h>
#include <fnmatch.h>

# ifndef DIRECTORY_SEPARATOR
#  define DIRECTORY_SEPARATOR '/'
# endif

# ifndef ISSLASH
#  define ISSLASH(C) ((C) == DIRECTORY_SEPARATOR)
# endif

/* Return 1 if an array of N objects, each of size S, cannot exist due
   to size arithmetic overflow.  S must be positive and N must be
   nonnegative.  This is a macro, not an inline function, so that it
   works correctly even when SIZE_MAX < N.

   By gnulib convention, SIZE_MAX represents overflow in size
   calculations, so the conservative dividend to use here is
   SIZE_MAX - 1, since SIZE_MAX might represent an overflowed value.
   However, malloc (SIZE_MAX) fails on all known hosts where
   sizeof (ptrdiff_t) <= sizeof (size_t), so do not bother to test for
   exactly-SIZE_MAX allocations on such hosts; this avoids a test and
   branch when S is known to be 1.  */
# define xalloc_oversized(n, s) \
    ((size_t) (sizeof (ptrdiff_t) <= sizeof (size_t) ? -1 : -2) / (s) < (n))

#define DISK_IO_BLOCK_SIZE	(512)

char *progname = NULL;

/* If true, print a . for each file processed. (-V) */
char dot_flag = false;

/* Input and output buffers.  */
char *input_buffer, *output_buffer;

/* The size of the input buffer.  */
long input_buffer_size;

/* Current locations in `input_buffer' and `output_buffer'.  */
char *in_buff, *out_buff;

/* Current number of bytes stored at `input_buff' and `output_buff'.  */
long input_size, output_size;

/* Block size value, initially 512.  -B sets to 5120.  */
int io_block_size = 512;

struct new_cpio_header {
	unsigned short c_magic;
	union {
		struct {
			unsigned long c_ino;
			unsigned long c_mode;
			unsigned long c_uid;
			unsigned long c_gid;
			unsigned long c_nlink;
			unsigned long c_mtime;
			unsigned long c_filesize;
			long c_dev_maj;
			long c_dev_min;
			long c_rdev_maj;
			long c_rdev_min;
			unsigned long c_namesize;
			unsigned long c_chksum;
		};
		unsigned long c_hdr[13];
	};
	char *c_name;
	char *c_tar_linkname;
};

/* Total number of bytes read and written for all files.
 * Now that many tape drives hold more than 4Gb we need more than 32
 *  bits to hold input_bytes and output_bytes.
 */
long long input_bytes, output_bytes;

/* Allocate N bytes of memory dynamically, with error checking.  */

static void *xmalloc(size_t n)
{
	void *p;
	if (xalloc_oversized(n, 1) || (!(p = malloc(n)) && n != 0)) {
		fprintf(stderr, "%s: memory exhausted\n", progname);
		exit(1);
	}
	return p;
/*   return xnmalloc_inline (n, 1); */
}

/* Clone STRING.  */

static char *xstrdup(char const *string)
{
	size_t s = strlen(string) + 1;
	return memcpy(xmalloc(s), string, s);
/*   return xmemdup_inline (string, strlen (string) + 1); */
}

/* Copy NUM_BYTES of buffer `in_buff' into IN_BUF.
   `in_buff' may be partly full.
   When `in_buff' is exhausted, refill it from file descriptor IN_DES.  */

static void tape_fill_input_buffer(int in_des, int num_bytes)
{
	in_buff = input_buffer;
	num_bytes = (num_bytes < io_block_size) ? num_bytes : io_block_size;
	input_size = read(in_des, input_buffer, num_bytes);
	if (input_size < 0) {
		fprintf(stderr, "%s: read error: %s\n", progname,
			strerror(errno));
		exit(1);
	}
	if (input_size == 0) {
		fprintf(stderr, "%s: premature end of file\n", progname);
		exit(1);
	}
	input_bytes += input_size;
}

/* Write `output_size' bytes of `output_buffer' to file
   descriptor OUT_DES and reset `output_size' and `out_buff'.
   If `swapping_halfwords' or `swapping_bytes' is set,
   do the appropriate swapping first.  Our callers have
   to make sure to only set these flags if `output_size'
   is appropriate (a multiple of 4 for `swapping_halfwords',
   2 for `swapping_bytes').  The fact that DISK_IO_BLOCK_SIZE
   must always be a multiple of 4 helps us (and our callers)
   insure this.  */

static void disk_empty_output_buffer(int out_des)
{
	int bytes_written;

	bytes_written = write(out_des, output_buffer, output_size);

	if (bytes_written != output_size) {
		fprintf(stderr, "%s: write error: %s\n",
			progname, strerror(errno));
		exit(1);
	}
	output_bytes += output_size;
	out_buff = output_buffer;
	output_size = 0;
}

/* Copy NUM_BYTES of buffer IN_BUF to `out_buff', which may be partly full.
   When `out_buff' fills up, flush it to file descriptor OUT_DES.  */

static void disk_buffered_write(char *in_buf, int out_des, long num_bytes)
{
	register long bytes_left = num_bytes;	/* Bytes needing to be copied.  */
	register long space_left;	/* Room left in output buffer.  */

	while (bytes_left > 0) {
		space_left = DISK_IO_BLOCK_SIZE - output_size;
		if (space_left == 0)
			disk_empty_output_buffer(out_des);
		else {
			if (bytes_left < space_left)
				space_left = bytes_left;
			memmove(out_buff, in_buf, (unsigned)space_left);
			out_buff += space_left;
			output_size += space_left;
			in_buf += space_left;
			bytes_left -= space_left;
		}
	}
}

/* Copy a file using the input and output buffers, which may start out
   partly full.  After the copy, the files are not closed nor the last
   block flushed to output, and the input buffer may still be partly
   full.  If `crc_i_flag' is set, add each byte to `crc'.
   IN_DES is the file descriptor for input;
   OUT_DES is the file descriptor for output;
   NUM_BYTES is the number of bytes to copy.  */

static void copy_files_tape_to_disk(int in_des, int out_des, long num_bytes)
{
	long size;

	while (num_bytes > 0) {
		if (input_size == 0)
			tape_fill_input_buffer(in_des, io_block_size);
		size = (input_size < num_bytes) ? input_size : num_bytes;
		disk_buffered_write(in_buff, out_des, size);
		num_bytes -= size;
		input_size -= size;
		in_buff += size;
	}
}

/* if IN_BUF is NULL, Skip the next NUM_BYTES bytes of file descriptor IN_DES. */
static void tape_buffered_read(char *in_buf, int in_des, long num_bytes)
{
	register long bytes_left = num_bytes;	/* Bytes needing to be copied.  */
	register long space_left;	/* Bytes to copy from input buffer.  */

	while (bytes_left > 0) {
		if (input_size == 0)
			tape_fill_input_buffer(in_des, io_block_size);
		if (bytes_left < input_size)
			space_left = bytes_left;
		else
			space_left = input_size;
		if (in_buf != NULL) {
			memmove(in_buf, in_buff, (unsigned)space_left);
			in_buf += space_left;
		}
		in_buff += space_left;
		input_size -= space_left;
		bytes_left -= space_left;
	}
}

/* Skip the next NUM_BYTES bytes of file descriptor IN_DES.  */
#define tape_toss_input(in_des,num_bytes) \
(tape_buffered_read(NULL,(in_des),(num_bytes)))

struct deferment {
	struct deferment *next;
	struct new_cpio_header header;
};

static struct deferment *create_deferment(struct new_cpio_header *file_hdr)
{
	struct deferment *d;
	d = (struct deferment *)xmalloc(sizeof(struct deferment));
	d->header = *file_hdr;
	d->header.c_name = (char *)xmalloc(strlen(file_hdr->c_name) + 1);
	strcpy(d->header.c_name, file_hdr->c_name);
	return d;
}

static void free_deferment(struct deferment *d)
{
	free(d->header.c_name);
	free(d);
}

static int link_to_name(char *link_name, char *link_target)
{
	int res = link(link_target, link_name);
	return res;
}

struct inode_val {
	unsigned long inode;
	unsigned long major_num;
	unsigned long minor_num;
	char *file_name;
};

/* Inode hash table.  Allocated by first call to add_inode.  */
static struct inode_val **hash_table = NULL;

/* Size of current hash table.  Initial size is 47.  (47 = 2*22 + 3) */
static int hash_size = 22;

/* Number of elements in current hash table.  */
static int hash_num;

/* Do the hash insert.  Used in normal inserts and resizing the hash
   table.  It is guaranteed that there is room to insert the item.
   NEW_VALUE is the pointer to the previously allocated inode, file
   name association record.  */

static void hash_insert(struct inode_val *new_value)
{
	int start;		/* Home position for the value.  */
	int temp;		/* Used for rehashing.  */

	/* Hash function is node number modulo the table size.  */
	start = new_value->inode % hash_size;

	/* Do the initial look into the table.  */
	if (hash_table[start] == NULL) {
		hash_table[start] = new_value;
		return;
	}

	/* If we get to here, the home position is full with a different inode
	   record.  Do a linear search for the first NULL pointer and insert
	   the new item there.  */
	temp = (start + 1) % hash_size;
	while (hash_table[temp] != NULL)
		temp = (temp + 1) % hash_size;

	/* Insert at the NULL.  */
	hash_table[temp] = new_value;
}

/* Associate FILE_NAME with the inode NODE_NUM.  (Insert into hash table.)  */

static void
add_inode(unsigned long node_num, char *file_name, unsigned long major_num,
	  unsigned long minor_num)
{
	struct inode_val *temp;

	/* Create new inode record.  */
	temp = (struct inode_val *)xmalloc(sizeof(struct inode_val));
	temp->inode = node_num;
	temp->major_num = major_num;
	temp->minor_num = minor_num;
	temp->file_name = xstrdup(file_name);

	/* Do we have to increase the size of (or initially allocate)
	   the hash table?  */
	if (hash_num == hash_size || hash_table == NULL) {
		struct inode_val **old_table;	/* Pointer to old table.  */
		int i;		/* Index for re-insert loop.  */

		/* Save old table.  */
		old_table = hash_table;
		if (old_table == NULL)
			hash_num = 0;

		/* Calculate new size of table and allocate it.
		   Sequence of table sizes is 47, 97, 197, 397, 797, 1597, 3197, 6397 ...
		   where 3197 and most of the sizes after 6397 are not prime.  The other
		   numbers listed are prime.  */
		hash_size = 2 * hash_size + 3;
		hash_table = (struct inode_val **)
		    xmalloc(hash_size * sizeof(struct inode_val *));
		memset(hash_table, 0, hash_size * sizeof(struct inode_val *));

		/* Insert the values from the old table into the new table.  */
		for (i = 0; i < hash_num; i++)
			hash_insert(old_table[i]);

		free(old_table);
	}

	/* Insert the new record and increment the count of elements in the
	   hash table.  */
	hash_insert(temp);
	hash_num++;
}

static char *find_inode_file(unsigned long node_num, unsigned long major_num,
		      unsigned long minor_num)
{
	int start;		/* Initial hash location.  */
	int temp;		/* Rehash search variable.  */

	if (hash_table != NULL) {
		/* Hash function is node number modulo the table size.  */
		start = node_num % hash_size;

		/* Initial look into the table.  */
		if (hash_table[start] == NULL)
			return NULL;
		if (hash_table[start]->inode == node_num
		    && hash_table[start]->major_num == major_num
		    && hash_table[start]->minor_num == minor_num)
			return hash_table[start]->file_name;

		/* The home position is full with a different inode record.
		   Do a linear search terminated by a NULL pointer.  */
		for (temp = (start + 1) % hash_size;
		     hash_table[temp] != NULL && temp != start;
		     temp = (temp + 1) % hash_size) {
			if (hash_table[temp]->inode == node_num
			    && hash_table[start]->major_num == major_num
			    && hash_table[start]->minor_num == minor_num)
				return hash_table[temp]->file_name;
		}
	}
	return NULL;
}

/* Try and create a hard link from FILE_NAME to another file
   with the given major/minor device number and inode.  If no other
   file with the same major/minor/inode numbers is known, add this file
   to the list of known files and associated major/minor/inode numbers
   and return -1.  If another file with the same major/minor/inode
   numbers is found, try and create another link to it using
   link_to_name, and return 0 for success and -1 for failure.  */

static int
link_to_maj_min_ino(char *file_name, int st_dev_maj, int st_dev_min, int st_ino)
{
	int link_res;
	char *link_name;
	link_res = -1;
	/* Is the file a link to a previously copied file?  */
	link_name = find_inode_file(st_ino, st_dev_maj, st_dev_min);
	if (link_name == NULL)
		add_inode(st_ino, file_name, st_dev_maj, st_dev_min);
	else
		link_res = link_to_name(file_name, link_name);
	return link_res;
}

static void copyin_regular_file(struct new_cpio_header *file_hdr,
				int in_file_des);

static void warn_junk_bytes(long bytes_skipped)
{
	fprintf(stderr, "%s: warning: skipped %ld byte(s) of junk\n",
		progname, bytes_skipped);
}

/* Skip the padding on IN_FILE_DES after a header or file,
   up to the next header.
   The number of bytes skipped is based on OFFSET -- the current offset
   from the last start of a header (or file) -- and the current
   header type.  */

static void tape_skip_padding(int in_file_des, int offset)
{
	int pad;
	pad = (4 - (offset % 4)) % 4;

	if (pad != 0)
		tape_toss_input(in_file_des, pad);
}

static int
try_existing_file(struct new_cpio_header *file_hdr, int in_file_des,
		  int *existing_dir)
{
	struct stat file_stat;

	*existing_dir = false;
	if (lstat(file_hdr->c_name, &file_stat) == 0) {
		if (S_ISDIR(file_stat.st_mode)
		    && ((file_hdr->c_mode & S_IFMT) == S_IFDIR)) {
			/* If there is already a directory there that
			   we are trying to create, don't complain about
			   it.  */
			*existing_dir = true;
			return 0;
		} else if (S_ISDIR(file_stat.st_mode)
			   ? rmdir(file_hdr->c_name)
			   : unlink(file_hdr->c_name)) {
			fprintf(stderr, "%s: cannot remove current %s: %s\n",
				progname, file_hdr->c_name, strerror(errno));
			tape_toss_input(in_file_des, file_hdr->c_filesize);
			tape_skip_padding(in_file_des, file_hdr->c_filesize);
			return -1;	/* Go to the next file.  */
		}
	}
	return 0;
}

/* The newc and crc formats store multiply linked copies of the same file
   in the archive only once.  The actual data is attached to the last link
   in the archive, and the other links all have a filesize of 0.  When a
   file in the archive has multiple links and a filesize of 0, its data is
   probably "attatched" to another file in the archive, so we can't create
   it right away.  We have to "defer" creating it until we have created
   the file that has the data "attatched" to it.  We keep a list of the
   "defered" links on deferments.  */

struct deferment *deferments = NULL;

/* Add a file header to the deferments list.  For now they all just
   go on one list, although we could optimize this if necessary.  */

static void defer_copyin(struct new_cpio_header *file_hdr)
{
	struct deferment *d;
	d = create_deferment(file_hdr);
	d->next = deferments;
	deferments = d;
	return;
}

/* We just created a file that (probably) has some other links to it
   which have been defered.  Go through all of the links on the deferments
   list and create any which are links to this file.  */

static void create_defered_links(struct new_cpio_header *file_hdr)
{
	struct deferment *d;
	struct deferment *d_prev;
	int ino;
	int maj;
	int min;
	int link_res;
	ino = file_hdr->c_ino;
	maj = file_hdr->c_dev_maj;
	min = file_hdr->c_dev_min;
	d = deferments;
	d_prev = NULL;
	while (d != NULL) {
		if ((d->header.c_ino == ino) && (d->header.c_dev_maj == maj)
		    && (d->header.c_dev_min == min)) {
			struct deferment *d_free;
			link_res =
			    link_to_name(d->header.c_name, file_hdr->c_name);
			if (link_res < 0) {
				fprintf(stderr,
					"%s: cannot link %s to %s: %s\n",
					progname, d->header.c_name,
					file_hdr->c_name, strerror(errno));
			}
			if (d_prev != NULL)
				d_prev->next = d->next;
			else
				deferments = d->next;
			d_free = d;
			d = d->next;
			free_deferment(d_free);
		} else {
			d_prev = d;
			d = d->next;
		}
	}
}

/* If we had a multiply linked file that really was empty then we would
   have defered all of its links, since we never found any with data
   "attached", and they will still be on the deferment list even when
   we are done reading the whole archive.  Write out all of these
   empty links that are still on the deferments list.  */

static void create_final_defers(void)
{
	struct deferment *d;
	int link_res;
	int out_file_des;
	struct utimbuf times;	/* For setting file times.  */
	/* Initialize this in case it has members we don't know to set.  */
	memset(&times, 0, sizeof(struct utimbuf));

	for (d = deferments; d != NULL; d = d->next) {
		/* Debian hack: A line, which could cause an endless loop, was
		   removed (97/1/2).  It was reported by Ronald F. Guilmette to
		   the upstream maintainers. -BEM */
		/* Debian hack:  This was reported by Horst Knobloch. This bug has
		   been reported to "bug-gnu-utils@prep.ai.mit.edu". (99/1/6) -BEM
		 */
		link_res = link_to_maj_min_ino(d->header.c_name,
					       d->header.c_dev_maj,
					       d->header.c_dev_min,
					       d->header.c_ino);
		if (link_res == 0) {
			continue;
		}
		out_file_des = open(d->header.c_name, O_CREAT | O_WRONLY, 0600);
		if (out_file_des < 0) {
			fprintf(stderr, "%s: open %s: %s\n",
				progname, d->header.c_name, strerror(errno));
			continue;
		}

		/* File is now copied; set attributes.  */
		if ((fchown(out_file_des, d->header.c_uid, d->header.c_gid) < 0)
		    && errno != EPERM)
			fprintf(stderr, "%s: fchown %s: %s\n",
				progname, d->header.c_name, strerror(errno));
		/* chown may have turned off some permissions we wanted. */
		if (fchmod(out_file_des, (int)d->header.c_mode) < 0)
			fprintf(stderr, "%s: fchmod %s: %s\n",
				progname, d->header.c_name, strerror(errno));

		if (close(out_file_des) < 0)
			fprintf(stderr, "%s: close %s: %s\n",
				progname, d->header.c_name, strerror(errno));

	}
}

static void
copyin_regular_file(struct new_cpio_header *file_hdr, int in_file_des)
{
	int out_file_des;	/* Output file descriptor.  */

	/* Can the current file be linked to a previously copied file? */
	if (file_hdr->c_nlink > 1) {
		int link_res;
		if (file_hdr->c_filesize == 0) {
			/* The newc and crc formats store multiply linked copies
			   of the same file in the archive only once.  The
			   actual data is attached to the last link in the
			   archive, and the other links all have a filesize
			   of 0.  Since this file has multiple links and a
			   filesize of 0, its data is probably attatched to
			   another file in the archive.  Save the link, and
			   process it later when we get the actual data.  We
			   can't just create it with length 0 and add the
			   data later, in case the file is readonly.  We still
			   lose if its parent directory is readonly (and we aren't
			   running as root), but there's nothing we can do about
			   that.  */
			defer_copyin(file_hdr);
			tape_toss_input(in_file_des, file_hdr->c_filesize);
			tape_skip_padding(in_file_des, file_hdr->c_filesize);
			return;
		}
		/* If the file has data (filesize != 0), then presumably
		   any other links have already been defer_copyin'ed(),
		   but GNU cpio version 2.0-2.2 didn't do that, so we
		   still have to check for links here (and also in case
		   the archive was created and later appeneded to). */
		/* Debian hack: (97/1/2) This was reported by Ronald
		   F. Guilmette to the upstream maintainers. -BEM */
		link_res = link_to_maj_min_ino(file_hdr->c_name,
					       file_hdr->c_dev_maj,
					       file_hdr->c_dev_min,
					       file_hdr->c_ino);
		if (link_res == 0) {
			tape_toss_input(in_file_des, file_hdr->c_filesize);
			tape_skip_padding(in_file_des, file_hdr->c_filesize);
			return;
		}
	}

	/* If not linked, copy the contents of the file.  */
	out_file_des = open(file_hdr->c_name, O_CREAT | O_WRONLY, 0600);

	if (out_file_des < 0) {
		fprintf(stderr, "%s: open %s: %s\n",
			progname, file_hdr->c_name, strerror(errno));
		tape_toss_input(in_file_des, file_hdr->c_filesize);
		tape_skip_padding(in_file_des, file_hdr->c_filesize);
		return;
	}

	copy_files_tape_to_disk(in_file_des, out_file_des,
				file_hdr->c_filesize);
	disk_empty_output_buffer(out_file_des);

	if (close(out_file_des) < 0)
		fprintf(stderr, "%s: close %s: %s\n",
			progname, file_hdr->c_name, strerror(errno));

	/* File is now copied; set attributes.  */
	if ((chown(file_hdr->c_name, file_hdr->c_uid, file_hdr->c_gid) < 0)
	    && errno != EPERM)
		fprintf(stderr, "%s: chown %s: %s\n",
			progname, file_hdr->c_name, strerror(errno));

	/* chown may have turned off some permissions we wanted. */
	if (chmod(file_hdr->c_name, (int)file_hdr->c_mode) < 0)
		fprintf(stderr, "%s: chmod %s: %s\n",
			progname, file_hdr->c_name, strerror(errno));

	tape_skip_padding(in_file_des, file_hdr->c_filesize);
	if (file_hdr->c_nlink > 1) {
		/* (see comment above for how the newc and crc formats
		   store multiple links).  Now that we have the data
		   for this file, create any other links to it which
		   we defered.  */
		create_defered_links(file_hdr);
	}
}

/* In general, we can't use the builtin `basename' function if available,
   since it has different meanings in different environments.
   In some environments the builtin `basename' modifies its argument.

   Return the address of the last file name component of NAME.  If
   NAME has no file name components because it is all slashes, return
   NAME if it is empty, the address of its last slash otherwise.  */

static char *base_name(char const *name)
{
	char const *base = name;
	char const *p;

	for (p = base; *p; p++) {
		if (ISSLASH(*p)) {
			/* Treat multiple adjacent slashes like a single slash.  */
			do
				p++;
			while (ISSLASH(*p));

			/* If the file name ends in slash, use the trailing slash as
			   the basename if no non-slashes have been found.  */
			if (!*p) {
				if (ISSLASH(*base))
					base = p - 1;
				break;
			}

			/* *P is a non-slash preceded by a slash.  */
			base = p;
		}
	}

	return (char *)base;
}

/* Return the length of of the basename NAME.  Typically NAME is the
   value returned by base_name.  Act like strlen (NAME), except omit
   redundant trailing slashes.  */

static size_t base_len(char const *name)
{
	size_t len;

	for (len = strlen(name); 1 < len && ISSLASH(name[len - 1]); len--)
		continue;

	return len;
}

/* Remove trailing slashes from PATH.
   Return true if a trailing slash was removed.
   This is useful when using filename completion from a shell that
   adds a "/" after directory names (such as tcsh and bash), because
   the Unix rename and rmdir system calls return an "Invalid argument" error
   when given a path that ends in "/" (except for the root directory).  */

static bool strip_trailing_slashes(char *path)
{
	char *base = base_name(path);
	char *base_lim = base + base_len(base);
	bool had_slash = (*base_lim != '\0');
	*base_lim = '\0';
	return had_slash;
}

static void copyin_directory(struct new_cpio_header *file_hdr, int existing_dir)
{
	int res;		/* Result of various function calls.  */

	/* Strip any trailing `/'s off the filename; tar puts
	   them on.  We might as well do it here in case anybody
	   else does too, since they cause strange things to happen.  */
	strip_trailing_slashes(file_hdr->c_name);

	/* Ignore the current directory.  It must already exist,
	   and we don't want to change its permission, ownership
	   or time.  */
	if (file_hdr->c_name[0] == '.' && file_hdr->c_name[1] == '\0') {
		return;
	}

	if (!existing_dir)
	{
		res = mkdir(file_hdr->c_name, file_hdr->c_mode);
	} else
		res = 0;
	if (res < 0) {
		/* In some odd cases where the file_hdr->c_name includes `.',
		   the directory may have actually been created by
		   create_all_directories(), so the mkdir will fail
		   because the directory exists.  If that's the case,
		   don't complain about it.  */
		struct stat file_stat;
		if ((errno != EEXIST) ||
		    (lstat(file_hdr->c_name, &file_stat) != 0) ||
		    !(S_ISDIR(file_stat.st_mode))) {
			fprintf(stderr, "%s: lstat %s: %s\n",
				progname, file_hdr->c_name, strerror(errno));
			return;
		}
	}
	if ((chown(file_hdr->c_name, file_hdr->c_uid, file_hdr->c_gid) < 0)
	    && errno != EPERM)
		fprintf(stderr, "%s: chown %s: %s\n",
			progname, file_hdr->c_name, strerror(errno));
	/* chown may have turned off some permissions we wanted. */
	if (chmod(file_hdr->c_name, (int)file_hdr->c_mode) < 0)
		fprintf(stderr, "%s: chmod %s: %s\n",
			progname, file_hdr->c_name, strerror(errno));
}

static void copyin_device(struct new_cpio_header *file_hdr)
{
	int res;		/* Result of various function calls.  */

	if (file_hdr->c_nlink > 1) {
		int link_res;
		/* Debian hack:  This was reported by Horst
		   Knobloch. This bug has been reported to
		   "bug-gnu-utils@prep.ai.mit.edu". (99/1/6) -BEM */
		link_res = link_to_maj_min_ino(file_hdr->c_name,
					       file_hdr->c_dev_maj,
					       file_hdr->c_dev_min,
					       file_hdr->c_ino);
		if (link_res == 0) {
			return;
		}
	}

	res = mknod(file_hdr->c_name, file_hdr->c_mode,
		    makedev(file_hdr->c_rdev_maj, file_hdr->c_rdev_min));
	if (res < 0) {
		fprintf(stderr, "%s: mknod %s: %s\n", progname,
			file_hdr->c_name, strerror(errno));
		return;
	}
	if ((chown(file_hdr->c_name, file_hdr->c_uid, file_hdr->c_gid) < 0)
	    && errno != EPERM)
		fprintf(stderr, "%s: chown %s: %s\n", progname,
			file_hdr->c_name, strerror(errno));
	/* chown may have turned off some permissions we wanted. */
	if (chmod(file_hdr->c_name, file_hdr->c_mode) < 0)
		fprintf(stderr, "%s: chmod %s: %s\n", progname,
			file_hdr->c_name, strerror(errno));
}

static void copyin_link(struct new_cpio_header *file_hdr, int in_file_des)
{
	char *link_name = NULL;	/* Name of hard and symbolic links.  */
	int res;		/* Result of various function calls.  */

	link_name = (char *)xmalloc(file_hdr->c_filesize + 1);
	link_name[file_hdr->c_filesize] = '\0';
	tape_buffered_read(link_name, in_file_des, file_hdr->c_filesize);
	tape_skip_padding(in_file_des, file_hdr->c_filesize);

	res = symlink(link_name, file_hdr->c_name);
	if (res < 0) {
		fprintf(stderr, "%s: symlink %s: %s\n",
			progname, file_hdr->c_name, strerror(errno));
		free(link_name);
		return;
	}
	if ((lchown(file_hdr->c_name, file_hdr->c_uid, file_hdr->c_gid) < 0)
	    && errno != EPERM) {
		fprintf(stderr, "%s: lchown %s: %s\n",
			progname, file_hdr->c_name, strerror(errno));
	}
	free(link_name);
}

static void copyin_file(struct new_cpio_header *file_hdr, int in_file_des)
{
	int existing_dir;

	if (try_existing_file(file_hdr, in_file_des, &existing_dir) < 0)
		return;

	/* Do the real copy or link.  */
	switch (file_hdr->c_mode & S_IFMT) {
	case S_IFREG:
		copyin_regular_file(file_hdr, in_file_des);
		break;

	case S_IFDIR:
		copyin_directory(file_hdr, existing_dir);
		break;

	case S_IFCHR:
	case S_IFBLK:
	case S_IFSOCK:
	case S_IFIFO:
		copyin_device(file_hdr);
		break;

	case S_IFLNK:
		copyin_link(file_hdr, in_file_des);
		break;

	default:
		fprintf(stderr, "%s: %s: unknown file type\n",
			progname, file_hdr->c_name);
		tape_toss_input(in_file_des, file_hdr->c_filesize);
		tape_skip_padding(in_file_des, file_hdr->c_filesize);
	}
}

/* Fill in FILE_HDR by reading a new-format ASCII format cpio header from
   file descriptor IN_DES, except for the magic number, which is
   already filled in.  */

static void read_in_new_ascii(struct new_cpio_header *file_hdr, int in_des)
{
	char ascii_header[13*8], *ah, hexbuf[9];
	int i;

	tape_buffered_read(ascii_header, in_des, 13*8);
	ah = ascii_header;
	hexbuf[8] = '\0';
	for (i = 0; i < 13; i++) {
		memcpy(hexbuf, ah, 8);
		file_hdr->c_hdr[i] = strtoul(hexbuf, NULL, 16);
		ah += 8;
	}

	/* Sizes > LONG_MAX can currently result in integer overflow
	   in various places.  Fail if name is too large. */
	if (file_hdr->c_namesize > LONG_MAX) {
		fprintf(stderr, "%s: name size out of range\n",
			progname);
		exit(1);
	}

	/* Read file name from input.  */
	free(file_hdr->c_name);
	file_hdr->c_name = (char *)xmalloc(file_hdr->c_namesize);
	tape_buffered_read(file_hdr->c_name, in_des,
			   (long)file_hdr->c_namesize);

	/* In SVR4 ASCII format, the amount of space allocated for the header
	   is rounded up to the next long-word, so we might need to drop
	   1-3 bytes.  */
	tape_skip_padding(in_des, file_hdr->c_namesize + 110);

	/* Fail if file is too large.  We could check this earlier
	   but it's helpful to report the name. */
	if (file_hdr->c_filesize > LONG_MAX) {
		fprintf(stderr, "%s: %s: file size out of range\n",
			progname, file_hdr->c_name);
		exit(1);
	}
}

/* Return 16-bit integer I with the bytes swapped.  */
#define swab_short(i) ((((i) << 8) & 0xff00) | (((i) >> 8) & 0x00ff))

/* Read the header, including the name of the file, from file
   descriptor IN_DES into FILE_HDR.  */

static void read_in_header(struct new_cpio_header *file_hdr, int in_des)
{
	long bytes_skipped = 0;	/* Bytes of junk found before magic number.  */

	/* Search for a valid magic number.  */

	file_hdr->c_tar_linkname = NULL;

	tape_buffered_read((char *)file_hdr, in_des, 6L);
	while (1) {
		if (!strncmp((char *)file_hdr, "070702", 6)
		    || !strncmp((char *)file_hdr, "070701", 6))
		{
			if (bytes_skipped > 0)
				warn_junk_bytes(bytes_skipped);

			read_in_new_ascii(file_hdr, in_des);
			break;
		}
		bytes_skipped++;
		memmove((char *)file_hdr, (char *)file_hdr + 1, 5);
		tape_buffered_read((char *)file_hdr + 5, in_des, 1L);
	}
}

/* Read the collection from standard input and create files
   in the file system.  */

static void process_copy_in(void)
{
	char done = false;	/* True if trailer reached.  */
	struct new_cpio_header file_hdr;	/* Output header information.  */
	int in_file_des;	/* Input file descriptor.  */

	/* Initialize the copy in.  */
	file_hdr.c_name = NULL;

	/* only from stdin */
	in_file_des = 0;

	/* While there is more input in the collection, process the input.  */
	while (!done) {
		/* Start processing the next file by reading the header.  */
		read_in_header(&file_hdr, in_file_des);

		/* Is this the header for the TRAILER file?  */
		if (strcmp("TRAILER!!!", file_hdr.c_name) == 0) {
			done = true;
			break;
		}

		/* Copy the input file into the directory structure.  */

		copyin_file(&file_hdr, in_file_des);

		if (dot_flag)
			fputc('.', stderr);
	}

	if (dot_flag)
		fputc('\n', stderr);

	create_final_defers();

}

/* Initialize the input and output buffers to their proper size and
   initialize all variables associated with the input and output
   buffers.  */

static void initialize_buffers(void)
{
	int in_buf_size, out_buf_size;

	/* Make sure the input buffer can always hold 2 blocks and that it
	   is big enough to hold 1 tar record (512 bytes) even if it
	   is not aligned on a block boundary.  The extra buffer space
	   is needed by process_copyin and peek_in_buf to automatically
	   figure out what kind of archive it is reading.  */
	if (io_block_size >= 512)
		in_buf_size = 2 * io_block_size;
	else
		in_buf_size = 1024;
	out_buf_size = DISK_IO_BLOCK_SIZE;

	input_buffer = (char *)xmalloc(in_buf_size);
	in_buff = input_buffer;
	input_buffer_size = in_buf_size;
	input_size = 0;
	input_bytes = 0;

	output_buffer = (char *)xmalloc(out_buf_size);
	out_buff = output_buffer;
	output_size = 0;
	output_bytes = 0;

}

int main(int argc, char *argv[])
{
	int c;
	int extract_flag = false;

	progname = argv[0];

	do {
		c = getopt(argc, argv, "iV");
		if (c == EOF)
			break;
		switch (c) {
		case 'V':
			dot_flag = true;
			break;

		case 'i':
			extract_flag = true;
			break;
		case '?':
			fprintf(stderr,
				"%s: not implemented or invalid option -%c\n",
				progname, optopt);
			exit(1);

		}
	} while (1);

	if (extract_flag) {
		initialize_buffers();

		process_copy_in();
	} else {
		fprintf(stderr, "Usage: %s [-V] -i [< archive]\n", progname);
		exit(1);
	}

	return 0;
}
