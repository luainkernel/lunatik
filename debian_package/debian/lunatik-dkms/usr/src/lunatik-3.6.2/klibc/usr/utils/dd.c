#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ARRAY_SIZE(x)	(sizeof(x) / sizeof(x[0]))

static char *progname;

struct option {
	const char *opt;
	char *str;
	char *arg;
};

struct conv {
	const char str[8];
	unsigned int set;
	unsigned int exclude;
};

#define CONV_BLOCK	(1<<0)
#define CONV_UNBLOCK	(1<<1)

#define CONV_LCASE	(1<<2)
#define CONV_UCASE	(1<<3)

#define CONV_SWAB	(1<<4)
#define CONV_NOERROR	(1<<5)
#define CONV_NOTRUNC	(1<<6)
#define CONV_SYNC	(1<<7)

static struct option options[] = {
	{"bs", NULL, NULL},
#define OPT_BS		(&options[0])
	{"cbs", NULL, NULL},
#define OPT_CBS		(&options[1])
	{"conv", NULL, NULL},
#define OPT_CONV	(&options[2])
	{"count", NULL, NULL},
#define OPT_COUNT	(&options[3])
	{"ibs", NULL, NULL},
#define OPT_IBS		(&options[4])
	{"if", NULL, NULL},
#define OPT_IF		(&options[5])
	{"obs", NULL, NULL},
#define OPT_OBS		(&options[6])
	{"of", NULL, NULL},
#define OPT_OF		(&options[7])
	{"seek", NULL, NULL},
#define OPT_SEEK	(&options[8])
	{"skip", NULL, NULL}
#define OPT_SKIP	(&options[9])
};

static const struct conv conv_opts[] = {
	{"block", CONV_BLOCK, CONV_UNBLOCK},
	{"unblock", CONV_UNBLOCK, CONV_BLOCK},
	{"lcase", CONV_LCASE, CONV_UCASE},
	{"ucase", CONV_UCASE, CONV_LCASE},
	{"swab", CONV_SWAB, 0},
	{"noerror", CONV_NOERROR, 0},
	{"notrunc", CONV_NOTRUNC, 0},
	{"sync", CONV_SYNC, 0},
};

static size_t cbs;
static unsigned int conv;
static unsigned int count;
static size_t ibs = 512;
static size_t obs = 512;
static unsigned int seek;
static unsigned int skip;
static char *in_buf;
static char *out_buf;

static size_t parse_bs(struct option *opt)
{
	unsigned long val, realval = 1;
	char *str = opt->str;
	int err = 0;

	do {
		char *s = str;
		val = strtoul(str, &str, 10);
		if (s == str || (val == ULONG_MAX && errno == ERANGE)) {
			err = 1;
			break;
		}

		/*
		 * This option may be followed by
		 * 'b', 'k' or 'x'
		 */
		if (*str == 'b') {
			val *= 512;
			str++;
		} else if (*str == 'k') {
			val *= 1024;
			str++;
		}
		realval *= val;
		if (*str != 'x')
			break;
		str++;
	} while (1);

	if (*str != '\0')
		err = 1;

	if (err) {
		fprintf(stderr, "%s: bad operand `%s'\n", progname, opt->arg);
		exit(1);
	}

	return (size_t) realval;
}

static unsigned int parse_num(struct option *opt)
{
	unsigned long val;
	char *str = opt->str;

	val = strtoul(str, &str, 10);
	if (str == opt->str || (val == ULONG_MAX && errno == ERANGE) ||
	    val > UINT_MAX) {
		fprintf(stderr, "%s: bad operand `%s'\n", progname, opt->arg);
		exit(1);
	}

	return (unsigned int)val;
}

static int parse_options(int argc, char *argv[])
{
	unsigned int i;
	char *p, *s;
	int arg;

	/*
	 * We cheat here; we don't parse the operand values
	 * themselves here.  We merely split the operands
	 * up.  This means that bs=foo bs=1 won't produce
	 * an error.
	 */
	for (arg = 1; arg < argc; arg++) {
		unsigned int len;

		s = strchr(argv[arg], '=');
		if (!s)
			s = argv[arg];	/* don't recognise this arg */

		len = s - argv[arg];
		for (i = 0; i < ARRAY_SIZE(options); i++) {
			if (strncmp(options[i].opt, argv[arg], len) != 0)
				continue;

			options[i].str = s + 1;
			options[i].arg = argv[arg];
			break;
		}

		if (i == ARRAY_SIZE(options)) {
			fprintf(stderr, "%s: bad operand `%s'\n",
				progname, argv[arg]);
			return 1;
		}
	}

	/*
	 * Translate numeric operands.
	 */
	if (OPT_IBS->str)
		ibs = parse_bs(OPT_IBS);
	if (OPT_OBS->str)
		obs = parse_bs(OPT_OBS);
	if (OPT_CBS->str)
		cbs = parse_bs(OPT_CBS);
	if (OPT_COUNT->str)
		count = parse_num(OPT_COUNT);
	if (OPT_SEEK->str)
		seek = parse_num(OPT_SEEK);
	if (OPT_SKIP->str)
		skip = parse_num(OPT_SKIP);

	/*
	 * If bs= is specified, it overrides ibs= and obs=
	 */
	if (OPT_BS->str)
		ibs = obs = parse_bs(OPT_BS);

	/*
	 * And finally conv=
	 */
	if (OPT_CONV->str) {
		p = OPT_CONV->str;

		while ((s = strsep(&p, ",")) != NULL) {
			for (i = 0; i < ARRAY_SIZE(conv_opts); i++) {
				if (strcmp(s, conv_opts[i].str) != 0)
					continue;
				conv &= ~conv_opts[i].exclude;
				conv |= conv_opts[i].set;
				break;
			}

			if (i == ARRAY_SIZE(conv_opts)) {
				fprintf(stderr, "%s: bad conversion `%s'\n",
					progname, s);
				return 1;
			}
		}
	}

	if (conv & (CONV_BLOCK | CONV_UNBLOCK) && cbs == 0) {
		fprintf(stderr, "%s: block/unblock conversion with zero cbs\n",
			progname);
		return 1;
	}

	return 0;
}

static int safe_read(int fd, void *buf, size_t size)
{
	int ret, count = 0;
	char *p = buf;

	while (size) {
		ret = read(fd, p, size);

		/*
		 * If we got EINTR, go again.
		 */
		if (ret == -1 && errno == EINTR)
			continue;

		/*
		 * If we encountered an error condition
		 * or read 0 bytes (EOF) return what we
		 * have.
		 */
		if (ret == -1 || ret == 0)
			return count ? count : ret;

		/*
		 * We read some bytes.
		 */
		count += ret;
		size -= ret;
		p += ret;
	}

	return count;
}

static int skip_blocks(int fd, void *buf, unsigned int blks, size_t size)
{
	unsigned int blk;
	int ret = 0;

	/*
	 * Try to seek.
	 */
	for (blk = 0; blk < blks; blk++) {
		ret = lseek(fd, size, SEEK_CUR);
		if (ret == -1)
			break;
	}

	/*
	 * If we failed to seek, read instead.
	 * FIXME: we don't handle short reads here, or
	 * EINTR correctly.
	 */
	if (blk == 0 && ret == -1 && errno == ESPIPE) {
		for (blk = 0; blk < blks; blk++) {
			ret = safe_read(fd, buf, size);
			if (ret != (int)size)
				break;
		}
	}

	if (ret == -1) {
		perror("seek/skip");
		return 1;
	}
	return 0;
}

struct stats {
	unsigned int in_full;
	unsigned int in_partial;
	unsigned int out_full;
	unsigned int out_partial;
	unsigned int truncated;
};

static int do_dd(int rd, int wr, struct stats *stats)
{
	unsigned int i;
	int ret;
	int fill_val = 0;
	size_t out_size = 0;
	size_t in_size;
	char *buf;

	if (conv & (CONV_BLOCK | CONV_UNBLOCK))
		fill_val = ' ';

	while (!OPT_COUNT->str || count-- != 0) {
		buf = in_buf;

		/*
		 * 1. read ibs-sized buffer
		 */
		in_size = ret = read(rd, in_buf, ibs);
		if (ret == -1 || (ret == 0 && (conv & CONV_NOERROR) == 0))
			break;

		if (in_size == ibs) {
			stats->in_full++;
		} else {
			stats->in_partial++;

			/*
			 * 2. zero (or append spaces)
			 */
			if (conv & CONV_SYNC) {
				memset(in_buf + in_size, fill_val,
				       ibs - in_size);
				in_size = ibs;
			}
		}

		/*
		 * 4. swab conversion.  With an odd number of bytes,
		 * last byte does not get swapped.
		 */
		if (conv & CONV_SWAB) {
			char c;

			for (i = 1; i < in_size; i += 2) {
				c = in_buf[i - 1];
				in_buf[i - 1] = in_buf[i];
				in_buf[i] = c;
			}
		}

		/*
		 * 5. remaining conversions.
		 */
		if (conv & CONV_LCASE)
			for (i = 0; i < in_size; i++)
				in_buf[i] = tolower(in_buf[i]);

		if (conv & CONV_UCASE)
			for (i = 0; i < in_size; i++)
				in_buf[i] = toupper(in_buf[i]);

		/* block/unblock ? */

		/*
		 * 6. Aggregate into obs sized buffers.
		 * If the in_size is obs-sized and we have no
		 * data waiting, just write "buf" to the output.
		 */
		if (out_size == 0 && in_size == obs) {
			write(wr, buf, obs);
			stats->out_full++;
		} else {
			/*
			 * We had data waiting, or we didn't have an
			 * obs-sized input block.  We need to append
			 * the input data to the output buffer.
			 */
			unsigned int space;
			char *in_ptr = in_buf;

			do {
				space = obs - out_size;
				if (space > in_size)
					space = in_size;

				memcpy(out_buf + out_size, in_ptr, space);
				out_size += space;
				in_size -= space;
				in_ptr += space;

				if (out_size == obs) {
					write(wr, out_buf, obs);
					stats->out_full++;
					out_size = 0;
				}
			} while (out_size == 0 && in_size);

			if (in_size) {
				memcpy(out_buf, in_ptr, in_size);
				out_size = in_size;
			}
		}
	}

	if (out_size) {
		write(wr, out_buf, out_size);
		stats->out_partial++;
	}

	return 0;
}

static sigjmp_buf jmp;

static void sigint_handler(int sig)
{
	siglongjmp(jmp, -sig);
}

static int dd(int rd_fd, int wr_fd, struct stats *stats)
{
	int ret;

	ret = sigsetjmp(jmp, 1);
	if (ret == 0) {
		sysv_signal(SIGINT, sigint_handler);
		ret = do_dd(rd_fd, wr_fd, stats);
	}

	sysv_signal(SIGINT, SIG_DFL);
	return ret;
}

int main(int argc, char *argv[])
{
	struct stats stats;
	int ret;
	int rd_fd = 0, wr_fd = 1;

	progname = argv[0];

	ret = parse_options(argc, argv);
	if (ret)
		return ret;

	if (conv & (CONV_BLOCK | CONV_UNBLOCK)) {
		fprintf(stderr, "%s: block/unblock not implemented\n",
			progname);
		return 1;
	}

	in_buf = malloc(ibs);
	if (!in_buf) {
		perror("malloc ibs");
		return 1;
	}

	out_buf = malloc(obs);
	if (!out_buf) {
		perror("malloc obs");
		return 1;
	}

	/*
	 * Open the input file, if specified.
	 */
	if (OPT_IF->str) {
		rd_fd = open(OPT_IF->str, O_RDONLY);
		if (rd_fd == -1) {
			perror("open input file");
			return 1;
		}
	}

	/*
	 * Open the output file, if specified.
	 */
	if (OPT_OF->str) {
		int flags = O_WRONLY|O_CREAT;
		flags |= (conv & CONV_NOTRUNC) ? 0 : O_TRUNC;
		wr_fd = open(OPT_OF->str, flags, 0666);
		if (wr_fd == -1) {
			perror("open output file");
			close(rd_fd);
			return 1;
		}
	}

	/*
	 * Skip obs-sized blocks of output file.
	 */
	if (OPT_SEEK->str && skip_blocks(wr_fd, out_buf, seek, obs)) {
		close(rd_fd);
		close(wr_fd);
		return 1;
	}

	/*
	 * Skip ibs-sized blocks of input file.
	 */
	if (OPT_SKIP->str && skip_blocks(rd_fd, in_buf, skip, ibs)) {
		close(rd_fd);
		close(wr_fd);
		return 1;
	}

	memset(&stats, 0, sizeof(stats));

	/*
	 * Do the real work
	 */
	ret = dd(rd_fd, wr_fd, &stats);

	if (close(rd_fd) == -1)
		perror(OPT_IF->str ? OPT_IF->str : "stdin");
	if (close(wr_fd) == -1)
		perror(OPT_OF->str ? OPT_OF->str : "stdout");

	fprintf(stderr, "%u+%u records in\n", stats.in_full, stats.in_partial);
	fprintf(stderr, "%u+%u records out\n",
		stats.out_full, stats.out_partial);
	if (stats.truncated)
		fprintf(stderr, "%u truncated record%s\n",
			stats.truncated, stats.truncated == 1 ? "" : "s");

	/*
	 * ret will be -SIGINT if we got a SIGINT.  Raise
	 * the signal again to cause us to terminate with
	 * SIGINT status.
	 */
	if (ret == -SIGINT)
		raise(SIGINT);

	return ret;
}
