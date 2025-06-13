#include <stdio.h>
#include <string.h>

int main(void)
{
	const char haystack[] = "haystack";
	const char empty[] = "";
	const char *p;
	size_t len;

	p = strchr(haystack, 'a');
	printf("found 'a' at offset %zd\n", p ? p - haystack : -1);
	if (p != haystack + 1)
		goto error;
	p = strchr(haystack, 'b');
	printf("found 'b' at offset %zd\n", p ? p - haystack : -1);
	if (p != NULL)
		goto error;
	p = strchr(haystack, 0);
	printf("found 0 at offset %zd\n", p ? p - haystack : -1);
	if (p != haystack + 8)
		goto error;

	p = strrchr(haystack, 'a');
	printf("found 'a' at offset %zd\n", p ? p - haystack : -1);
	if (p != haystack + 5)
		goto error;
	p = strrchr(haystack, 'b');
	printf("found 'b' at offset %zd\n", p ? p - haystack : -1);
	if (p != NULL)
		goto error;
	p = strrchr(haystack, 0);
	printf("found 0 at offset %zd\n", p ? p - haystack : -1);
	if (p != haystack + 8)
		goto error;

	len = strspn(haystack, "hasty");
	printf("found %zu chars from 'hasty'\n", len);
	if (len != 6)
		goto error;
	len = strspn(haystack, "haystack");
	printf("found %zu chars from 'haystack'\n", len);
	if (len != 8)
		goto error;
	len = strspn(haystack, "");
	printf("found %zu chars from ''\n", len);
	if (len != 0)
		goto error;

	len = strcspn(haystack, "stick");
	printf("found %zu chars not from 'stick'\n", len);
	if (len != 3)
		goto error;
	len = strcspn(haystack, "needle");
	printf("found %zu chars not from 'needle'\n", len);
	if (len != 8)
		goto error;
	len = strcspn(haystack, "");
	printf("found %zu chars not from ''\n", len);
	if (len != 8)
		goto error;

	p = strpbrk(haystack, "stick");
	printf("found char from 'stick' at offset %zd\n", p ? p - haystack : -1);
	if (p != haystack + 3)
		goto error;
	p = strpbrk(haystack, "needle");
	printf("found char from 'needle' at offset %zd\n", p ? p - haystack : -1);
	if (p != NULL)
		goto error;
	p = strpbrk(haystack, "");
	printf("found char from '' at offset %zd\n", p ? p - haystack : -1);
	if (p != NULL)
		goto error;

	p = strstr(haystack, "stack");
	printf("found 'stack' at offset %zd\n", p ? p - haystack : -1);
	if (p != haystack + 3)
		goto error;
	p = strstr(haystack, "tacks");
	printf("found 'tacks' at offset %zd\n", p ? p - haystack : -1);
	if (p != NULL)
		goto error;
	p = strstr(haystack, "needle");
	printf("found 'needle' at offset %zd\n", p ? p - haystack : -1);
	if (p != NULL)
		goto error;
	p = strstr(haystack, "k");
	printf("found 'k' at offset %zd\n", p ? p - haystack : -1);
	if (p != haystack + 7)
		goto error;
	p = strstr(haystack, "b");
	printf("found 'b' at offset %zd\n", p ? p - haystack : -1);
	if (p != NULL)
		goto error;
	p = strstr(haystack, "kk");
	printf("found 'kk' at offset %zd\n", p ? p - haystack : -1);
	if (p != NULL)
		goto error;
	p = strstr(haystack, "");
	printf("found '' at offset %zd\n", p ? p - haystack : -1);
	if (p != haystack)
		goto error;
	p = strstr(empty, "");
	printf("found '' at offset %zd\n", p ? p - empty : -1);
	if (p != empty)
		goto error;

	return 0;
error:
	printf("unexpected result\n");
	return 1;
}
