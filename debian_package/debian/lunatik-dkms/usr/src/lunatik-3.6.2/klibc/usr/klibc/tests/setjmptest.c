/*
 * setjmptest.c
 */

#include <stdio.h>
#include <setjmp.h>

static jmp_buf buf;

void do_stuff(int v)
{
	printf("calling longjmp with %d... ", v + 1);
	longjmp(buf, v + 1);
}

void recurse(int ctr, int v)
{
	if (ctr--)
		recurse(ctr, v);
	else
		do_stuff(v);

	printf("ERROR!\n");	/* We should never get here... */
}

int main(void)
{
	int v;

	v = setjmp(buf);
	printf("setjmp returned %d\n", v);

	if (v < 256)
		recurse(v, v);

	return 0;
}
