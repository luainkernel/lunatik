#define __NO_STDIO_INLINES
#include "stdioint.h"

int ferror(FILE *__f)
{
	return __f->_IO_error;
}
__ALIAS(int, ferror_unlocked, (FILE *), ferror)
