#include <stdio.h>
#include <mntent.h>

int endmntent(FILE *fp)
{
	if (fp)
		fclose(fp);
	return 1;
}
