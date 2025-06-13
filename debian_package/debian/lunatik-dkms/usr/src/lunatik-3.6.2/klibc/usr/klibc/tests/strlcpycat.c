#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
	char temp[8];
	size_t len;

	printf("strlcpy:\n");
	len = strlcpy(temp, "123", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "123") != 0)
		goto error;

	len = strlcpy(temp, "", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "") != 0)
		goto error;

	len = strlcpy(temp, "1234567890", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "1234567") != 0)
		goto error;

	len = strlcpy(temp, "123", 1);
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "") != 0)
		goto error;

	len = strlcpy(temp, "1234567890", 1);
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "") != 0)
		goto error;

	len = strlcpy(temp, "123", 0);
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "") != 0)
		goto error;

	len = strlcpy(temp, "1234567890", 0);
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "") != 0)
		goto error;

	len = strlcpy(temp, "1234567", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "1234567") != 0)
		goto error;

	len = strlcpy(temp, "12345678", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "1234567") != 0)
		goto error;

	printf("\n");
	printf("strlcat:\n");
	strcpy(temp, "");
	len = strlcat(temp, "123", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "123") != 0)
		goto error;

	strcpy(temp, "ABC");
	len = strlcat(temp, "", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "ABC") != 0)
		goto error;

	strcpy(temp, "");
	len = strlcat(temp, "", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "") != 0)
		goto error;

	strcpy(temp, "ABC");
	len = strlcat(temp, "123", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "ABC123") != 0)
		goto error;

	strcpy(temp, "ABC");
	len = strlcat(temp, "1234567890", sizeof(temp));
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "ABC1234") != 0)
		goto error;

	strcpy(temp, "ABC");
	len = strlcat(temp, "123", 5);
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "ABC1") != 0)
		goto error;

	strcpy(temp, "ABC");
	len = strlcat(temp, "123", 1);
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "ABC") != 0)
		goto error;

	strcpy(temp, "ABC");
	len = strlcat(temp, "123", 0);
	printf("'%s'len:%zu strlen:%zu\n", temp, len, strlen(temp));
	if (strcmp(temp, "ABC") != 0)
		goto error;

	exit(0);
error:
	printf("unexpected result\n");
	exit(1);
}
