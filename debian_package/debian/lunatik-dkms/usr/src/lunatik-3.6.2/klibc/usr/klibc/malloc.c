/*
 * malloc.c
 *
 * Very simple linked-list based malloc()/free().
 */

#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <assert.h>
#include <errno.h>
#include "malloc.h"

/* Both the arena list and the free memory list are double linked
   list with head node.  This the head node. Note that the arena list
   is sorted in order of address. */
static struct free_arena_header __malloc_head = {
	{
		ARENA_TYPE_HEAD,
		0,
		&__malloc_head,
		&__malloc_head,
	},
	&__malloc_head,
	&__malloc_head
};

static inline void mark_block_dead(struct free_arena_header *ah)
{
#ifdef DEBUG_MALLOC
	ah->a.type = ARENA_TYPE_DEAD;
#endif
}

static inline void remove_from_main_chain(struct free_arena_header *ah)
{
	struct free_arena_header *ap, *an;

	mark_block_dead(ah);

	ap = ah->a.prev;
	an = ah->a.next;
	ap->a.next = an;
	an->a.prev = ap;
}

static inline void remove_from_free_chain(struct free_arena_header *ah)
{
	struct free_arena_header *ap, *an;

	ap = ah->prev_free;
	an = ah->next_free;
	ap->next_free = an;
	an->prev_free = ap;
}

static inline void remove_from_chains(struct free_arena_header *ah)
{
	remove_from_free_chain(ah);
	remove_from_main_chain(ah);
}

static void *__malloc_from_block(struct free_arena_header *fp, size_t size)
{
	size_t fsize;
	struct free_arena_header *nfp, *na, *fpn, *fpp;

	fsize = fp->a.size;

	/* We need the 2* to account for the larger requirements of a
	   free block */
	if (fsize >= size + 2 * sizeof(struct arena_header)) {
		/* Bigger block than required -- split block */
		nfp = (struct free_arena_header *)((char *)fp + size);
		na = fp->a.next;

		nfp->a.type = ARENA_TYPE_FREE;
		nfp->a.size = fsize - size;
		fp->a.type = ARENA_TYPE_USED;
		fp->a.size = size;

		/* Insert into all-block chain */
		nfp->a.prev = fp;
		nfp->a.next = na;
		na->a.prev = nfp;
		fp->a.next = nfp;

		/* Replace current block on free chain */
		nfp->next_free = fpn = fp->next_free;
		nfp->prev_free = fpp = fp->prev_free;
		fpn->prev_free = nfp;
		fpp->next_free = nfp;
	} else {
		fp->a.type = ARENA_TYPE_USED; /* Allocate the whole block */
		remove_from_free_chain(fp);
	}

	return (void *)(&fp->a + 1);
}

static struct free_arena_header *__free_block(struct free_arena_header *ah)
{
	struct free_arena_header *pah, *nah;

	pah = ah->a.prev;
	nah = ah->a.next;
	if (pah->a.type == ARENA_TYPE_FREE &&
	    (char *)pah + pah->a.size == (char *)ah) {
		/* Coalesce into the previous block */
		pah->a.size += ah->a.size;
		pah->a.next = nah;
		nah->a.prev = pah;
		mark_block_dead(ah);

		ah = pah;
		pah = ah->a.prev;
	} else {
		/* Need to add this block to the free chain */
		ah->a.type = ARENA_TYPE_FREE;

		ah->next_free = __malloc_head.next_free;
		ah->prev_free = &__malloc_head;
		__malloc_head.next_free = ah;
		ah->next_free->prev_free = ah;
	}

	/* In either of the previous cases, we might be able to merge
	   with the subsequent block... */
	if (nah->a.type == ARENA_TYPE_FREE &&
	    (char *)ah + ah->a.size == (char *)nah) {
		ah->a.size += nah->a.size;

		/* Remove the old block from the chains */
		remove_from_chains(nah);
	}

	/* Return the block that contains the called block */
	return ah;
}

void *malloc(size_t size)
{
	struct free_arena_header *fp;
	struct free_arena_header *pah;
	size_t fsize;

	if (size == 0)
		return NULL;

	/* Various additions below will overflow if size is close to
	   SIZE_MAX.  Further, it's not legal for a C object to be
	   larger than PTRDIFF_MAX (half of SIZE_MAX) as pointer
	   arithmetic within it could overflow. */
	if (size > PTRDIFF_MAX) {
		errno = ENOMEM;
		return NULL;
	}

	/* Add the obligatory arena header, and round up */
	size = (size + 2 * sizeof(struct arena_header) - 1) & ARENA_SIZE_MASK;

	for (fp = __malloc_head.next_free; fp->a.type != ARENA_TYPE_HEAD;
	     fp = fp->next_free) {
		if (fp->a.size >= size) {
			/* Found fit -- allocate out of this block */
			return __malloc_from_block(fp, size);
		}
	}

	/* Nothing found... need to request a block from the kernel */
	fsize = (size + MALLOC_CHUNK_MASK) & ~MALLOC_CHUNK_MASK;

#if _KLIBC_MALLOC_USES_SBRK
	if (fsize > INTPTR_MAX) {
		errno = ENOMEM;
		return NULL;
	}
	fp = (struct free_arena_header *)sbrk(fsize);
#else
	fp = (struct free_arena_header *)
	    mmap(NULL, fsize, PROT_READ | PROT_WRITE,
		 MAP_PRIVATE | MAP_ANONYMOUS, 0, 0);
#endif

	if (fp == (struct free_arena_header *)MAP_FAILED) {
		errno = ENOMEM;
		return NULL;	/* Failed to get a block */
	}

	/* Insert the block into the management chains.  We need to set
	   up the size and the main block list pointer, the rest of
	   the work is logically identical to free(). */
	fp->a.type = ARENA_TYPE_FREE;
	fp->a.size = fsize;

	/* We need to insert this into the main block list in the proper
	   place -- this list is required to be sorted.  Since we most likely
	   get memory assignments in ascending order, search backwards for
	   the proper place. */
	for (pah = __malloc_head.a.prev; pah->a.type != ARENA_TYPE_HEAD;
	     pah = pah->a.prev) {
		if (pah < fp)
			break;
	}

	/* Now pah points to the node that should be the predecessor of
	   the new node */
	fp->a.next = pah->a.next;
	fp->a.prev = pah;
	pah->a.next = fp;
	fp->a.next->a.prev = fp;

	/* Insert into the free chain and coalesce with adjacent blocks */
	fp = __free_block(fp);

	/* Now we can allocate from this block */
	return __malloc_from_block(fp, size);
}

void free(void *ptr)
{
	struct free_arena_header *ah;

	if (!ptr)
		return;

	ah = (struct free_arena_header *)
	    ((struct arena_header *)ptr - 1);

#ifdef DEBUG_MALLOC
	assert(ah->a.type == ARENA_TYPE_USED);
#endif

	/* Merge into adjacent free blocks */
	ah = __free_block(ah);

	/* See if it makes sense to return memory to the system */
#if _KLIBC_MALLOC_USES_SBRK
	if (ah->a.size >= _KLIBC_MALLOC_CHUNK_SIZE &&
	    (char *)ah + ah->a.size == __current_brk) {
		remove_from_chains(ah);
		brk(ah);
	}
#else
	{
		size_t page_size = getpagesize();
		size_t page_mask = page_size - 1;
		size_t head_portion = -(size_t)ah & page_mask;
		size_t tail_portion = ((size_t)ah + ah->a.size) & page_mask;
		size_t adj_size;

		/* Careful here... an individual chunk of memory must have
		   a minimum size if it exists at all, so if either the
		   head or the tail is below the minimum, then extend
		   that chunk by a page. */

		if (head_portion &&
		    head_portion < 2*sizeof(struct arena_header))
			head_portion += page_size;

		if (tail_portion &&
		    tail_portion < 2*sizeof(struct arena_header))
			tail_portion += page_size;

		adj_size = ah->a.size - head_portion - tail_portion;

		/* Worth it?  This is written the way it is to guard
		   against overflows... */
		if (ah->a.size >= head_portion+tail_portion+
		    _KLIBC_MALLOC_CHUNK_SIZE) {
			struct free_arena_header *tah, *tan, *tap;

			if (tail_portion) {
				/* Make a new header, and insert into chains
				   immediately after the current block */
				tah = (struct free_arena_header *)
					((char *)ah + head_portion + adj_size);
				tah->a.type = ARENA_TYPE_FREE;
				tah->a.size = tail_portion;
				tah->a.next = tan = ah->a.next;
				tan->a.prev = tah;
				tah->a.prev = ah;
				ah->a.next = tah;
				tah->prev_free = tap = ah->prev_free;
				tap->next_free = tah;
				tah->next_free = ah;
				ah->prev_free = tah;
			}

			if (head_portion)
				ah->a.size = head_portion;
			else
				remove_from_chains(ah);

			munmap((char *)ah + head_portion, adj_size);
		}
	}
#endif
}
