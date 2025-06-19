#define __NO_STDIO_INLINES
#include "stdioint.h"

int fileno(FILE *__f)
{
	return __f->_IO_fileno;
}
__ALIAS(int, fileno_unlocked, (FILE *), fileno)
