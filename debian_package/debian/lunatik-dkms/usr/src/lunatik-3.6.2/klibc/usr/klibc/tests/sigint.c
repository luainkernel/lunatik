#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

static sig_atomic_t counter = 0;

static void sig_handler(int signum)
{
	static const char msg[] = "Signal handler\n";

	(void)signum;

	write(1, msg, sizeof msg - 1);
	counter++;
}

int main(int argc, char *argv[])
{
	struct sigaction act, oact;
	pid_t f;
	sigset_t set;

	(void)argc;

	memset(&act, 0x00, sizeof(struct sigaction));
	act.sa_handler = sig_handler;
	sigemptyset(&act.sa_mask);
	act.sa_flags = SA_RESTART;

	/* oact is there for the benefit of strace() */
	sigaction(SIGINT, &act, &oact);
	sigaction(SIGTERM, &act, &oact);

	sigemptyset(&set);
	sigaddset(&set, SIGINT);
	sigprocmask(SIG_BLOCK, &set, NULL);

	f = fork();

	if (f < 0) {
		perror(argv[0]);
		exit(255);
	} else if (f > 0) {
		sleep(3);
		if (counter) {
			fprintf(stderr, "Signal received while masked!\n");
			exit(1);
		}
		sigprocmask(SIG_UNBLOCK, &set, NULL);
		sleep(3);
		if (!counter) {
			fprintf(stderr, "No signal received!\n");
			exit(1);
		} else {
			printf("Signal received OK\n");
			exit(0);
		}
	} else {
		sleep(1);
		kill(getppid(), SIGINT);
		_exit(0);
	}
}
