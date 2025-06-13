/*
 * fgets.c
 */

#include <stdio.h>

char *fgets(char *s, int n, FILE *f)
{
	int ch;
	char *p = s;

	while (n > 1) {
		ch = getc(f);
		if (ch == EOF) {
			s = NULL;
			break;
		}
		*p++ = ch;
		n--;
		if (ch == '\n')
			break;
	}
	if (n)
		*p = '\0';

	return s;
}
__ALIAS(char *, fgets_unlocked, (char *, int, FILE *), fgets)
