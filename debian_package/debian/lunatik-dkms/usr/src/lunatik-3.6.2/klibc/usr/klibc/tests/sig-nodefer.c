/*
 * Expected output of ./sig-nodefer:
 * SIGUSR2: blocked
 * SIGTERM: blocked
 */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

void handler(int signum)
{
	sigset_t mask;

	sigprocmask(SIG_BLOCK, NULL, &mask);
	printf("SIGUSR2: %s\n",
		sigismember(&mask, SIGUSR2) ? "blocked" : "not blocked");
	printf("SIGTERM: %s\n",
		sigismember(&mask, SIGTERM) ? "blocked" : "not blocked");
}

int main(int argc, char **argv)
{
	pid_t pid;

	pid = fork();
	if (pid == -1) {
		perror("fork");
		exit(EXIT_FAILURE);
	} else if (!pid) {
		struct sigaction act;

		memset(&act, 0, sizeof(act));
		act.sa_handler = handler;
		act.sa_flags = SA_NODEFER;

		sigaddset(&act.sa_mask, SIGUSR2);
		sigaddset(&act.sa_mask, SIGTERM);

		sigaction(SIGUSR1, &act, NULL);

		pause();
	} else {
		int status;

		sleep(3);
		kill(pid, SIGUSR1);
		waitpid(pid, &status, 0);
	}

	return 0;
}
