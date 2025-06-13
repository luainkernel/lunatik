#include <unistd.h>
#include <sys/syscall.h>

#ifndef __NR_pipe

int pipe(int pipefd[2])
{
	return pipe2(pipefd, 0);
}

#endif  /* __NR_pipe */
