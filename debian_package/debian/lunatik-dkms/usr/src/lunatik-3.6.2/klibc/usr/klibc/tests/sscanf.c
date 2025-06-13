#include <stdio.h>

int main()
{
	int ret, err = 0, e1, e2;
	const char a1[] = "3.0", a2[] = "-12,1000";

	/* int tests */
	ret = sscanf(a1, "%1d", &e1);
	if (ret != 1) {
		printf("Error wrong sscanf int return %d.\n", ret);
		err++;
	}
	if (e1 != 3) {
		printf("Error wrong sscanf int reading %d.\n", e1);
		err++;
	}
	ret = sscanf(a2, "%3d,%4d", &e1, &e2);
	if (ret != 2) {
		printf("Error wrong sscanf int return %d.\n", ret);
		err++;
	}
	if (e1 != -12) {
		printf("Error wrong sscanf int reading %d.\n", e1);
		err++;
	}
	if (e2 != 1000) {
		printf("Error wrong sscanf int reading %d.\n", e2);
		err++;
	}
	/* XXX: add more int tests */

	if (err)
		return err;
	return 0;
}
