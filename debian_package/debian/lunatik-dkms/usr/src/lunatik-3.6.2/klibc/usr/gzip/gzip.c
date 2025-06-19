/* gzip (GNU zip) -- compress files with zip algorithm and 'compress' interface
 * Copyright (C) 1992-1993 Jean-loup Gailly
 * The unzip code was written and put in the public domain by Mark Adler.
 * Portions of the lzw code are derived from the public domain 'compress'
 * written by Spencer Thomas, Joe Orost, James Woods, Jim McKie, Steve Davies,
 * Ken Turkowski, Dave Mack and Peter Jannesen.
 *
 * See the license_msg below and the file COPYING for the software license.
 * See the file algorithm.doc for the compression algorithms and file formats.
 */

static char  *license_msg[] = {
"   Copyright (C) 1992-1993 Jean-loup Gailly",
"   This program is free software; you can redistribute it and/or modify",
"   it under the terms of the GNU General Public License as published by",
"   the Free Software Foundation; either version 2, or (at your option)",
"   any later version.",
"",
"   This program is distributed in the hope that it will be useful,",
"   but WITHOUT ANY WARRANTY; without even the implied warranty of",
"   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the",
"   GNU General Public License for more details.",
"",
"   You should have received a copy of the GNU General Public License",
"   along with this program; if not, write to the Free Software",
"   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.",
0};

/* Compress files with zip algorithm and 'compress' interface.
 * See usage() and help() functions below for all options.
 * Outputs:
 *        file.gz:   compressed file with same mode, owner, and utimes
 *     or stdout with -c option or if stdin used as input.
 * If the output file name had to be truncated, the original name is kept
 * in the compressed file.
 * On MSDOS, file.tmp -> file.tmz. On VMS, file.tmp -> file.tmp-gz.
 *
 * Using gz on MSDOS would create too many file name conflicts. For
 * example, foo.txt -> foo.tgz (.tgz must be reserved as shorthand for
 * tar.gz). Similarly, foo.dir and foo.doc would both be mapped to foo.dgz.
 * I also considered 12345678.txt -> 12345txt.gz but this truncates the name
 * too heavily. There is no ideal solution given the MSDOS 8+3 limitation.
 *
 * For the meaning of all compilation flags, see comments in Makefile.in.
 */

#ifdef RCSID
static char rcsid[] = "$Id: gzip.c,v 1.3 2005/02/12 21:03:28 olh Exp $";
#endif

#include <ctype.h>
#include <sys/types.h>
#include <signal.h>
#include <sys/stat.h>
#include <errno.h>

#include "tailor.h"
#include "gzip.h"
#include "revision.h"

#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>

#include <utime.h>

typedef void (*sig_type) OF((int));

#define RW_USER (S_IRUSR | S_IWUSR)  /* creation mode for open() */

#ifndef MAX_PATH_LEN
#  define MAX_PATH_LEN   1024 /* max pathname length */
#endif

		/* global buffers */

DECLARE(uch, inbuf,  INBUFSIZ +INBUF_EXTRA);
DECLARE(uch, outbuf, OUTBUFSIZ+OUTBUF_EXTRA);
DECLARE(ush, d_buf,  DIST_BUFSIZE);
DECLARE(uch, window, 2L*WSIZE);
DECLARE(ush, tab_prefix, 1L<<BITS);

		/* local variables */

#ifndef SUPPORT_ZIP
#define decompress 1
#else
int level = 6;        /* compression level */
#endif

int to_stdout;        /* output to stdout (-c) */
#ifdef decompress
int decompress_wanted;
#else
int decompress;       /* decompress (-d) */
#define decompress_wanted decompress
#endif
int force;            /* don't ask questions, compress links (-f) */
int no_name = -1;     /* don't save or restore the original file name */
int no_time = -1;     /* don't save or restore the original file time */
int verbose;          /* be verbose (-v) */
int quiet;            /* be very quiet (-q) */
int test;             /* test .gz file integrity */
int foreground;       /* set if program run in foreground */
char *progname;       /* program name */
int method = DEFLATED;/* compression method */
int exit_code = OK;   /* program exit code */
int save_orig_name;   /* set if original name must be saved */
int last_member;      /* set for .zip and .Z files */
int part_nb;          /* number of parts in .gz file */
time_t time_stamp; /* original time stamp (modification time) */
long ifile_size;      /* input file size, -1 for devices (debug only) */
char *env;            /* contents of GZIP env variable */
char **args = NULL;   /* argv pointer if GZIP env variable defined */
char z_suffix[MAX_SUFFIX+1]; /* default suffix (can be set with --suffix) */
int  z_len;           /* strlen(z_suffix) */

long header_bytes;	   /* number of bytes in gzip header */
long bytes_in;             /* number of input bytes */
long bytes_out;            /* number of output bytes */
long total_in;             /* input bytes for all files */
long total_out;            /* output bytes for all files */
char ifname[MAX_PATH_LEN]; /* input file name */
char ofname[MAX_PATH_LEN]; /* output file name */
int  remove_ofname;	   /* remove output file on error */
struct stat istat;         /* status for input file */
int  ifd;                  /* input file descriptor */
int  ofd;                  /* output file descriptor */
unsigned insize;           /* valid bytes in inbuf */
unsigned inptr;            /* index of next byte to be processed in inbuf */
unsigned outcnt;           /* bytes in output buffer */

/* local functions */

local void usage        OF((void));
local void help         OF((void));
local void license      OF((void));
local void version      OF((void));
local void treat_stdin  OF((void));
local void treat_file   OF((char *iname));
local int create_outfile OF((void));
local int  do_stat      OF((char *name, struct stat *sbuf));
local char *get_suffix  OF((char *name));
local int  get_istat    OF((char *iname, struct stat *sbuf));
local int  make_ofname  OF((void));
local int  same_file    OF((struct stat *stat1, struct stat *stat2));
local int name_too_long OF((char *name, struct stat *statb));
local void shorten_name  OF((char *name));
local int  get_method   OF((void));
local int  check_ofname OF((void));
local void copy_stat    OF((struct stat *ifstat));
local void do_exit      OF((int exitcode));
      int main          OF((int argc, char **argv));
int (*work) OF((int infile, int outfile))
#ifdef SUPPORT_ZIP
 = zip; /* function to call */
#else
 = unzip;
#endif
local void reset_times  OF((char *name, struct stat *statb));

#define strequ(s1, s2) (strcmp((s1),(s2)) == 0)

/* ======================================================================== */
local void usage()
{
    fprintf(stderr, "usage: %s [-cdfhlLnNtvV19] [-S suffix] [file ...]\n",
	    progname);
}

/* ======================================================================== */
local void help()
{
    static char  *help_msg[] = {
 " -c --stdout      write on standard output, keep original files unchanged",
 " -d --decompress  decompress",
 " -f --force       force overwrite of output file and compress links",
 " -h --help        give this help",
 " -L --license     display software license",
#ifdef UNDOCUMENTED
 " -m --no-time     do not save or restore the original modification time",
 " -M --time        save or restore the original modification time",
#endif
 " -n --no-name     do not save or restore the original name and time stamp",
 " -N --name        save or restore the original name and time stamp",
 " -q --quiet       suppress all warnings",
 " -S .suf  --suffix .suf     use suffix .suf on compressed files",
 " -t --test        test compressed file integrity",
 " -v --verbose     verbose mode",
 " -V --version     display version number",
#ifdef SUPPORT_ZIP
 " -1 --fast        compress faster",
 " -9 --best        compress better",
 " file...          files to (de)compress. If none given, use standard input.",
#else
 " file...          files to decompress. If none given, use standard input.",
#endif
  0};
    char **p = help_msg;

    fprintf(stderr,"%s %s (%s)\n", progname, VERSION, REVDATE);
    usage();
    while (*p) fprintf(stderr, "%s\n", *p++);
}

/* ======================================================================== */
local void license()
{
    char **p = license_msg;

    fprintf(stderr,"%s %s (%s)\n", progname, VERSION, REVDATE);
    while (*p) fprintf(stderr, "%s\n", *p++);
}

/* ======================================================================== */
local void version()
{
    fprintf(stderr,"%s %s (%s)\n", progname, VERSION, REVDATE);

    fprintf(stderr, "Compilation options: UTIME STDC_HEADERS"
#ifndef SUPPORT_ZIP
	" DECOMPRESS_ONLY"
#endif
	"\n");
}

/* ======================================================================== */
int main (argc, argv)
    int argc;
    char **argv;
{
    int file_count;     /* number of files to precess */
    int optc;           /* current option */

    progname = basename(argv[0]);

    /* Add options in GZIP environment variable if there is one */
    env = add_envopt(&argc, &argv, OPTIONS_VAR);
    if (env != NULL) args = argv;

    foreground = sysv_signal(SIGINT, SIG_IGN) != SIG_IGN;
    if (foreground) {
	(void) sysv_signal(SIGINT, (sig_type)abort_gzip);
    }
#ifdef SIGTERM
    if (sysv_signal(SIGTERM, SIG_IGN) != SIG_IGN) {
	(void) sysv_signal(SIGTERM, (sig_type)abort_gzip);
    }
#endif
#ifdef SIGHUP
    if (sysv_signal(SIGHUP, SIG_IGN) != SIG_IGN) {
	(void) sysv_signal(SIGHUP,  (sig_type)abort_gzip);
    }
#endif

#ifndef GNU_STANDARD
    /* For compatibility with old compress, use program name as an option.
     * If you compile with -DGNU_STANDARD, this program will behave as
     * gzip even if it is invoked under the name gunzip or zcat.
     *
     * Systems which do not support links can still use -d or -dc.
     * Ignore an .exe extension for MSDOS, OS/2 and VMS.
     */
    if (  strncmp(progname, "un",  2) == 0     /* ungzip, uncompress */
       || strncmp(progname, "gun", 3) == 0) {  /* gunzip */
	decompress_wanted = 1;
    }
    if (strequ(progname+1, "cat")       /* zcat, pcat, gcat */
	|| strequ(progname, "gzcat")) {    /* gzcat */
	decompress_wanted = 1;
	to_stdout = 1;
    }
#endif

    strncpy(z_suffix, Z_SUFFIX, sizeof(z_suffix)-1);
    z_len = strlen(z_suffix);

    while ((optc = getopt(argc, argv, "cdfhH?LmMnNqrS:tvV123456789")) != EOF) {
	switch (optc) {
	case 'c':
	    to_stdout = 1; break;
	case 'd':
	    decompress_wanted = 1;
	    break;
	case 'f':
	    force++; break;
	case 'h': case 'H': case '?':
	    help(); do_exit(OK); break;
	case 'L':
	    license(); do_exit(OK); break;
	case 'm': /* undocumented, may change later */
	    no_time = 1; break;
	case 'M': /* undocumented, may change later */
	    no_time = 0; break;
	case 'n':
	    no_name = no_time = 1; break;
	case 'N':
	    no_name = no_time = 0; break;
	case 'q':
	    quiet = 1; verbose = 0; break;
	case 'S':
            z_len = strlen(optarg);
            strcpy(z_suffix, optarg);
            break;
	case 't':
	    test = to_stdout = 1;
	    decompress_wanted = 1;
	    break;
	case 'v':
	    verbose++; quiet = 0; break;
	case 'V':
	    version(); do_exit(OK); break;
#ifdef SUPPORT_ZIP
	case '1':  case '2':  case '3':  case '4':
	case '5':  case '6':  case '7':  case '8':  case '9':
	    level = optc - '0';
	    break;
#endif
	default:
	    /* Error message already emitted by getopt_long. */
	    usage();
	    do_exit(ERROR);
	}
    } /* loop on all arguments */

#ifndef SUPPORT_ZIP
    if (!decompress_wanted) {
	fprintf(stderr, "%s: this version does not support compression\n",
		progname);
	do_exit(ERROR);
    }
#endif

    /* By default, save name and timestamp on compression but do not
     * restore them on decompression.
     */
    if (no_time < 0) no_time = decompress;
    if (no_name < 0) no_name = decompress;

    file_count = argc - optind;

    if ((z_len == 0 && !decompress) || z_len > MAX_SUFFIX) {
        fprintf(stderr, "%s: incorrect suffix '%s'\n",
                progname, optarg);
        do_exit(ERROR);
    }

    /* Allocate all global buffers (for DYN_ALLOC option) */
    ALLOC(uch, inbuf,  INBUFSIZ +INBUF_EXTRA);
    ALLOC(uch, outbuf, OUTBUFSIZ+OUTBUF_EXTRA);
    ALLOC(ush, d_buf,  DIST_BUFSIZE);
    ALLOC(uch, window, 2L*WSIZE);
    ALLOC(ush, tab_prefix, 1L<<BITS);

    /* And get to work */
    if (file_count != 0) {
        while (optind < argc) {
	    treat_file(argv[optind++]);
	}
    } else {  /* Standard input */
	treat_stdin();
    }
    do_exit(exit_code);
    return exit_code; /* just to avoid lint warning */
}

/* ========================================================================
 * Compress or decompress stdin
 */
local void treat_stdin()
{
    if (!force &&
	isatty(fileno((FILE *)(decompress ? stdin : stdout)))) {
	/* Do not send compressed data to the terminal or read it from
	 * the terminal. We get here when user invoked the program
	 * without parameters, so be helpful. According to the GNU standards:
	 *
	 *   If there is one behavior you think is most useful when the output
	 *   is to a terminal, and another that you think is most useful when
	 *   the output is a file or a pipe, then it is usually best to make
	 *   the default behavior the one that is useful with output to a
	 *   terminal, and have an option for the other behavior.
	 *
	 * Here we use the --force option to get the other behavior.
	 */
	fprintf(stderr,
    "%s: compressed data not %s a terminal. Use -f to force %scompression.\n",
		progname, decompress ? "read from" : "written to",
		decompress ? "de" : "");
	fprintf(stderr,"For help, type: %s -h\n", progname);
	do_exit(ERROR);
    }

    strcpy(ifname, "stdin");
    strcpy(ofname, "stdout");

    /* Get the time stamp on the input file. */
    time_stamp = 0; /* time unknown by default */

    if (!no_time) {
	if (fstat(fileno(stdin), &istat) != 0) {
	    error("fstat(stdin)");
	}
	time_stamp = istat.st_mtime;
    }
    ifile_size = -1L; /* convention for unknown size */

    clear_bufs(); /* clear input and output buffers */
    to_stdout = 1;
    part_nb = 0;

    if (decompress) {
	method = get_method();
	if (method < 0) {
	    do_exit(exit_code); /* error message already emitted */
	}
    }

    /* Actually do the compression/decompression. Loop over zipped members.
     */
    for (;;) {
	if ((*work)(fileno(stdin), fileno(stdout)) != OK) return;

	if (!decompress || last_member || inptr == insize) break;
	/* end of file */

	method = get_method();
	if (method < 0) return; /* error message already emitted */
	bytes_out = 0;            /* required for length check */
    }

    if (verbose) {
	if (test) {
	    fprintf(stderr, " OK\n");

	} else if (!decompress) {
	    display_ratio(bytes_in-(bytes_out-header_bytes), bytes_in, stderr);
	    fprintf(stderr, "\n");
#ifdef DISPLAY_STDIN_RATIO
	} else {
	    display_ratio(bytes_out-(bytes_in-header_bytes), bytes_out,stderr);
	    fprintf(stderr, "\n");
#endif
	}
    }
}

/* ========================================================================
 * Compress or decompress the given file
 */
local void treat_file(iname)
    char *iname;
{
    /* Accept "-" as synonym for stdin */
    if (strequ(iname, "-")) {
	int cflag = to_stdout;
	treat_stdin();
	to_stdout = cflag;
	return;
    }

    /* Check if the input file is present, set ifname and istat: */
    if (get_istat(iname, &istat) != OK) return;

    /* If the input name is that of a directory, recurse or ignore: */
    if (S_ISDIR(istat.st_mode)) {
	WARN((stderr,"%s: %s is a directory -- ignored\n", progname, ifname));
	return;
    }
    if (!S_ISREG(istat.st_mode)) {
	WARN((stderr,
	      "%s: %s is not a directory or a regular file - ignored\n",
	      progname, ifname));
	return;
    }
    if (istat.st_nlink > 1 && !to_stdout && !force) {
	WARN((stderr, "%s: %s has %d other link%c -- unchanged\n",
	      progname, ifname,
	      (int)istat.st_nlink - 1, istat.st_nlink > 2 ? 's' : ' '));
	return;
    }

    ifile_size = istat.st_size;
    time_stamp = no_time ? 0 : istat.st_mtime;

    /* Generate output file name. For -r and (-t or -l), skip files
     * without a valid gzip suffix (check done in make_ofname).
     */
    if (to_stdout && !test) {
	strcpy(ofname, "stdout");

    } else if (make_ofname() != OK) {
	return;
    }

    /* Open the input file and determine compression method. The mode
     * parameter is ignored but required by some systems (VMS) and forbidden
     * on other systems (MacOS).
     */
    ifd = open(ifname, !decompress ? O_RDONLY : O_RDONLY,
	       RW_USER);
    if (ifd == -1) {
	fprintf(stderr, "%s: ", progname);
	perror(ifname);
	exit_code = ERROR;
	return;
    }
    clear_bufs(); /* clear input and output buffers */
    part_nb = 0;

    if (decompress) {
	method = get_method(); /* updates ofname if original given */
	if (method < 0) {
	    close(ifd);
	    return;               /* error message already emitted */
	}
    }

    /* If compressing to a file, check if ofname is not ambiguous
     * because the operating system truncates names. Otherwise, generate
     * a new ofname and save the original name in the compressed file.
     */
    if (to_stdout) {
	ofd = fileno(stdout);
	/* keep remove_ofname as zero */
    } else {
	if (create_outfile() != OK) return;

	if (!decompress && save_orig_name && !verbose && !quiet) {
	    fprintf(stderr, "%s: %s compressed to %s\n",
		    progname, ifname, ofname);
	}
    }
    /* Keep the name even if not truncated except with --no-name: */
    if (!save_orig_name) save_orig_name = !no_name;

    if (verbose) {
	fprintf(stderr, "%s:\t%s", ifname, (int)strlen(ifname) >= 15 ?
		"" : ((int)strlen(ifname) >= 7 ? "\t" : "\t\t"));
    }

    /* Actually do the compression/decompression. Loop over zipped members.
     */
    for (;;) {
	if ((*work)(ifd, ofd) != OK) {
	    method = -1; /* force cleanup */
	    break;
	}
	if (!decompress || last_member || inptr == insize) break;
	/* end of file */

	method = get_method();
	if (method < 0) break;    /* error message already emitted */
	bytes_out = 0;            /* required for length check */
    }

    close(ifd);
    if (!to_stdout && close(ofd)) {
	write_error();
    }
    if (method == -1) {
	if (!to_stdout) unlink (ofname);
	return;
    }
    /* Display statistics */
    if(verbose) {
	if (test) {
	    fprintf(stderr, " OK");
	} else if (decompress) {
	    display_ratio(bytes_out-(bytes_in-header_bytes), bytes_out,stderr);
	} else {
	    display_ratio(bytes_in-(bytes_out-header_bytes), bytes_in, stderr);
	}
	if (!test && !to_stdout) {
	    fprintf(stderr, " -- replaced with %s", ofname);
	}
	fprintf(stderr, "\n");
    }
    /* Copy modes, times, ownership, and remove the input file */
    if (!to_stdout) {
	copy_stat(&istat);
    }
}

/* ========================================================================
 * Create the output file. Return OK or ERROR.
 * Try several times if necessary to avoid truncating the z_suffix. For
 * example, do not create a compressed file of name "1234567890123."
 * Sets save_orig_name to true if the file name has been truncated.
 * IN assertions: the input file has already been open (ifd is set) and
 *   ofname has already been updated if there was an original name.
 * OUT assertions: ifd and ofd are closed in case of error.
 */
local int create_outfile()
{
    struct stat	ostat; /* stat for ofname */
    int flags = O_WRONLY | O_CREAT | O_EXCL;

    for (;;) {
	/* Make sure that ofname is not an existing file */
	if (check_ofname() != OK) {
	    close(ifd);
	    return ERROR;
	}
	/* Create the output file */
	remove_ofname = 1;
	ofd = open(ofname, flags, RW_USER);
	if (ofd == -1) {
	    perror(ofname);
	    close(ifd);
	    exit_code = ERROR;
	    return ERROR;
	}

	/* Check for name truncation on new file (1234567890123.gz) */
	if (fstat(ofd, &ostat) != 0) {
	    fprintf(stderr, "%s: ", progname);
	    perror(ofname);
	    close(ifd); close(ofd);
	    unlink(ofname);
	    exit_code = ERROR;
	    return ERROR;
	}
	if (!name_too_long(ofname, &ostat)) return OK;

	if (decompress) {
	    /* name might be too long if an original name was saved */
	    WARN((stderr, "%s: %s: warning, name truncated\n",
		  progname, ofname));
	    return OK;
	}
	close(ofd);
	unlink(ofname);
	shorten_name(ofname);
    }
}

/* ========================================================================
 * Use lstat if available, except for -c or -f. Use stat otherwise.
 * This allows links when not removing the original file.
 */
local int do_stat(name, sbuf)
    char *name;
    struct stat *sbuf;
{
    errno = 0;
    if (!to_stdout && !force) {
	return lstat(name, sbuf);
    }
    return stat(name, sbuf);
}

/* ========================================================================
 * Return a pointer to the 'z' suffix of a file name, or NULL. For all
 * systems, ".gz", ".z", ".Z", ".taz", ".tgz", "-gz", "-z" and "_z" are
 * accepted suffixes, in addition to the value of the --suffix option.
 * ".tgz" is a useful convention for tar.z files on systems limited
 * to 3 characters extensions. On such systems, ".?z" and ".??z" are
 * also accepted suffixes. For Unix, we do not want to accept any
 * .??z suffix as indicating a compressed file; some people use .xyz
 * to denote volume data.
 *   On systems allowing multiple versions of the same file (such as VMS),
 * this function removes any version suffix in the given name.
 */
local char *get_suffix(name)
    char *name;
{
    int nlen, slen;
    char suffix[MAX_SUFFIX+3]; /* last chars of name, forced to lower case */
    static char *known_suffixes[] =
       {z_suffix, ".gz", ".z", ".taz", ".tgz", "-gz", "-z", "_z",
          NULL};
    char **suf = known_suffixes;

    if (strequ(z_suffix, "z")) suf++; /* check long suffixes first */

    nlen = strlen(name);
    if (nlen <= MAX_SUFFIX+2) {
        strcpy(suffix, name);
    } else {
        strcpy(suffix, name+nlen-MAX_SUFFIX-2);
    }
    strlwr(suffix);
    slen = strlen(suffix);
    do {
       int s = strlen(*suf);
       if (slen > s && suffix[slen-s-1] != PATH_SEP
           && strequ(suffix + slen - s, *suf)) {
           return name+nlen-s;
       }
    } while (*++suf != NULL);

    return NULL;
}


/* ========================================================================
 * Set ifname to the input file name (with a suffix appended if necessary)
 * and istat to its stats. For decompression, if no file exists with the
 * original name, try adding successively z_suffix, .gz, .z, -z and .Z.
 * For MSDOS, we try only z_suffix and z.
 * Return OK or ERROR.
 */
local int get_istat(iname, sbuf)
    char *iname;
    struct stat *sbuf;
{
    int ilen;  /* strlen(ifname) */
    static char *suffixes[] = {z_suffix, ".gz", ".z", "-z", ".Z", NULL};
    char **suf = suffixes;
    char *s;

    strcpy(ifname, iname);

    /* If input file exists, return OK. */
    if (do_stat(ifname, sbuf) == 0) return OK;

    if (!decompress || errno != ENOENT) {
	perror(ifname);
	exit_code = ERROR;
	return ERROR;
    }
    /* file.ext doesn't exist, try adding a suffix (after removing any
     * version number for VMS).
     */
    s = get_suffix(ifname);
    if (s != NULL) {
	perror(ifname); /* ifname already has z suffix and does not exist */
	exit_code = ERROR;
	return ERROR;
    }
    ilen = strlen(ifname);
    if (strequ(z_suffix, ".gz")) suf++;

    /* Search for all suffixes */
    do {
        s = *suf;
        strcat(ifname, s);
        if (do_stat(ifname, sbuf) == 0) return OK;
	ifname[ilen] = '\0';
    } while (*++suf != NULL);

    /* No suffix found, complain using z_suffix: */
    strcat(ifname, z_suffix);
    perror(ifname);
    exit_code = ERROR;
    return ERROR;
}

/* ========================================================================
 * Generate ofname given ifname. Return OK, or WARNING if file must be skipped.
 * Sets save_orig_name to true if the file name has been truncated.
 */
local int make_ofname()
{
    char *suff;            /* ofname z suffix */

    strcpy(ofname, ifname);
    /* strip a version number if any and get the gzip suffix if present: */
    suff = get_suffix(ofname);

    if (decompress) {
	if (suff == NULL) {
	    /* Whith -t or -l, try all files (even without .gz suffix)
	     * except with -r (behave as with just -dr).
             */
            if (test) return OK;

	    /* Avoid annoying messages with -r */
	    if (verbose || !quiet) {
		WARN((stderr,"%s: %s: unknown suffix -- ignored\n",
		      progname, ifname));
	    }
	    return WARNING;
	}
	/* Make a special case for .tgz and .taz: */
	strlwr(suff);
	if (strequ(suff, ".tgz") || strequ(suff, ".taz")) {
	    strcpy(suff, ".tar");
	} else {
	    *suff = '\0'; /* strip the z suffix */
	}
        /* ofname might be changed later if infile contains an original name */

    } else if (suff != NULL) {
	/* Avoid annoying messages with -r (see treat_dir()) */
	if (verbose || !quiet) {
	    fprintf(stderr, "%s: %s already has %s suffix -- unchanged\n",
		    progname, ifname, suff);
	}
	if (exit_code == OK) exit_code = WARNING;
	return WARNING;
    } else {
        save_orig_name = 0;
	strcat(ofname, z_suffix);

    } /* decompress ? */
    return OK;
}


/* ========================================================================
 * Check the magic number of the input file and update ofname if an
 * original name was given and to_stdout is not set.
 * Return the compression method, -1 for error, -2 for warning.
 * Set inptr to the offset of the next byte to be processed.
 * Updates time_stamp if there is one and --no-time is not used.
 * This function may be called repeatedly for an input file consisting
 * of several contiguous gzip'ed members.
 * IN assertions: there is at least one remaining compressed member.
 *   If the member is a zip file, it must be the only one.
 */
local int get_method()
{
    uch flags;     /* compression flags */
    char magic[2]; /* magic header */
    ulg stamp;     /* time stamp */

    /* If --force and --stdout, zcat == cat, so do not complain about
     * premature end of file: use try_byte instead of get_byte.
     */
    if (force && to_stdout) {
	magic[0] = (char)try_byte();
	magic[1] = (char)try_byte();
	/* If try_byte returned EOF, magic[1] == 0xff */
    } else {
	magic[0] = (char)get_byte();
	magic[1] = (char)get_byte();
    }
    method = -1;                 /* unknown yet */
    part_nb++;                   /* number of parts in gzip file */
    header_bytes = 0;
    last_member = RECORD_IO;
    /* assume multiple members in gzip file except for record oriented I/O */

    if (memcmp(magic, GZIP_MAGIC, 2) == 0
        || memcmp(magic, OLD_GZIP_MAGIC, 2) == 0) {

	method = (int)get_byte();
	if (method != DEFLATED) {
	    fprintf(stderr,
		    "%s: %s: unknown method %d -- get newer version of gzip\n",
		    progname, ifname, method);
	    exit_code = ERROR;
	    return -1;
	}
	work = unzip;
	flags  = (uch)get_byte();

	if ((flags & ENCRYPTED) != 0) {
	    fprintf(stderr,
		    "%s: %s is encrypted -- get newer version of gzip\n",
		    progname, ifname);
	    exit_code = ERROR;
	    return -1;
	}
	if ((flags & CONTINUATION) != 0) {
	    fprintf(stderr,
	   "%s: %s is a a multi-part gzip file -- get newer version of gzip\n",
		    progname, ifname);
	    exit_code = ERROR;
	    if (force <= 1) return -1;
	}
	if ((flags & RESERVED) != 0) {
	    fprintf(stderr,
		    "%s: %s has flags 0x%x -- get newer version of gzip\n",
		    progname, ifname, flags);
	    exit_code = ERROR;
	    if (force <= 1) return -1;
	}
	stamp  = (ulg)get_byte();
	stamp |= ((ulg)get_byte()) << 8;
	stamp |= ((ulg)get_byte()) << 16;
	stamp |= ((ulg)get_byte()) << 24;
	if (stamp != 0 && !no_time) time_stamp = stamp;

	(void)get_byte();  /* Ignore extra flags for the moment */
	(void)get_byte();  /* Ignore OS type for the moment */

	if ((flags & CONTINUATION) != 0) {
	    unsigned part = (unsigned)get_byte();
	    part |= ((unsigned)get_byte())<<8;
	    if (verbose) {
		fprintf(stderr,"%s: %s: part number %u\n",
			progname, ifname, part);
	    }
	}
	if ((flags & EXTRA_FIELD) != 0) {
	    unsigned len = (unsigned)get_byte();
	    len |= ((unsigned)get_byte())<<8;
	    if (verbose) {
		fprintf(stderr,"%s: %s: extra field of %u bytes ignored\n",
			progname, ifname, len);
	    }
	    while (len--) (void)get_byte();
	}

	/* Get original file name if it was truncated */
	if ((flags & ORIG_NAME) != 0) {
	    if (no_name || to_stdout || part_nb > 1) {
		/* Discard the old name */
		char c; /* dummy used for NeXTstep 3.0 cc optimizer bug */
		do {c=get_byte();} while (c != 0);
	    } else {
		/* Copy the base name. Keep a directory prefix intact. */
                char *p = basename(ofname);
		for (;;) {
		    *p = (char)get_char();
		    if (*p++ == '\0') break;
		    if (p >= ofname+sizeof(ofname)) {
			error("corrupted input -- file name too large");
		    }
		}
	    } /* no_name || to_stdout */
	} /* ORIG_NAME */

	/* Discard file comment if any */
	if ((flags & COMMENT) != 0) {
	    while (get_char() != 0) /* null */ ;
	}
	if (part_nb == 1) {
	    header_bytes = inptr + 2*sizeof(long); /* include crc and size */
	}
    } else if (force && to_stdout) { /* pass input unchanged */
	method = STORED;
	work = copy;
        inptr = 0;
	last_member = 1;
    }
    if (method >= 0) return method;

    if (part_nb == 1) {
	fprintf(stderr, "\n%s: %s: not in gzip format\n", progname, ifname);
	exit_code = ERROR;
	return -1;
    } else {
	WARN((stderr, "\n%s: %s: decompression OK, trailing garbage ignored\n",
	      progname, ifname));
	return -2;
    }
}


/* ========================================================================
 * Return true if the two stat structures correspond to the same file.
 */
local int same_file(stat1, stat2)
    struct stat *stat1;
    struct stat *stat2;
{
    return stat1->st_ino   == stat2->st_ino
	&& stat1->st_dev   == stat2->st_dev
#ifdef NO_ST_INO
        /* Can't rely on st_ino and st_dev, use other fields: */
	&& stat1->st_mode  == stat2->st_mode
	&& stat1->st_uid   == stat2->st_uid
	&& stat1->st_gid   == stat2->st_gid
	&& stat1->st_size  == stat2->st_size
	&& stat1->st_atime == stat2->st_atime
	&& stat1->st_mtime == stat2->st_mtime
	&& stat1->st_ctime == stat2->st_ctime
#endif
	    ;
}

/* ========================================================================
 * Return true if a file name is ambiguous because the operating system
 * truncates file names.
 */
local int name_too_long(name, statb)
    char *name;           /* file name to check */
    struct stat *statb;   /* stat buf for this file name */
{
    int s = strlen(name);
    char c = name[s-1];
    struct stat	tstat; /* stat for truncated name */
    int res;

    tstat = *statb;      /* Just in case OS does not fill all fields */
    name[s-1] = '\0';
    res = stat(name, &tstat) == 0 && same_file(statb, &tstat);
    name[s-1] = c;
    Trace((stderr, " too_long(%s) => %d\n", name, res));
    return res;
}

/* ========================================================================
 * Shorten the given name by one character, or replace a .tar extension
 * with .tgz. Truncate the last part of the name which is longer than
 * MIN_PART characters: 1234.678.012.gz -> 123.678.012.gz. If the name
 * has only parts shorter than MIN_PART truncate the longest part.
 * For decompression, just remove the last character of the name.
 *
 * IN assertion: for compression, the suffix of the given name is z_suffix.
 */
local void shorten_name(name)
    char *name;
{
    int len;                 /* length of name without z_suffix */
    char *trunc = NULL;      /* character to be truncated */
    int plen;                /* current part length */
    int min_part = MIN_PART; /* current minimum part length */
    char *p;

    len = strlen(name);
    if (decompress) {
	if (len <= 1) error("name too short");
	name[len-1] = '\0';
	return;
    }
    p = get_suffix(name);
    if (p == NULL) error("can't recover suffix\n");
    *p = '\0';
    save_orig_name = 1;

    /* compress 1234567890.tar to 1234567890.tgz */
    if (len > 4 && strequ(p-4, ".tar")) {
	strcpy(p-4, ".tgz");
	return;
    }
    /* Try keeping short extensions intact:
     * 1234.678.012.gz -> 123.678.012.gz
     */
    do {
	p = strrchr(name, PATH_SEP);
	p = p ? p+1 : name;
	while (*p) {
	    plen = strcspn(p, ".");
	    p += plen;
	    if (plen > min_part) trunc = p-1;
	    if (*p) p++;
	}
    } while (trunc == NULL && --min_part != 0);

    if (trunc != NULL) {
	do {
	    trunc[0] = trunc[1];
	} while (*trunc++);
	trunc--;
    } else {
	trunc = strrchr(name, '.');
	if (trunc == NULL) error("internal error in shorten_name");
	if (trunc[1] == '\0') trunc--; /* force truncation */
    }
    strcpy(trunc, z_suffix);
}

/* ========================================================================
 * If compressing to a file, check if ofname is not ambiguous
 * because the operating system truncates names. Otherwise, generate
 * a new ofname and save the original name in the compressed file.
 * If the compressed file already exists, ask for confirmation.
 *    The check for name truncation is made dynamically, because different
 * file systems on the same OS might use different truncation rules (on SVR4
 * s5 truncates to 14 chars and ufs does not truncate).
 *    This function returns -1 if the file must be skipped, and
 * updates save_orig_name if necessary.
 * IN assertions: save_orig_name is already set if ofname has been
 * already truncated because of NO_MULTIPLE_DOTS. The input file has
 * already been open and istat is set.
 */
local int check_ofname()
{
    struct stat	ostat; /* stat for ofname */

#ifdef ENAMETOOLONG
    /* Check for strictly conforming Posix systems (which return ENAMETOOLONG
     * instead of silently truncating filenames).
     */
    errno = 0;
    while (stat(ofname, &ostat) != 0) {
        if (errno != ENAMETOOLONG) return 0; /* ofname does not exist */
	shorten_name(ofname);
    }
#else
    if (stat(ofname, &ostat) != 0) return 0;
#endif
    /* Check for name truncation on existing file. Do this even on systems
     * defining ENAMETOOLONG, because on most systems the strict Posix
     * behavior is disabled by default (silent name truncation allowed).
     */
    if (!decompress && name_too_long(ofname, &ostat)) {
	shorten_name(ofname);
	if (stat(ofname, &ostat) != 0) return 0;
    }

    /* Check that the input and output files are different (could be
     * the same by name truncation or links).
     */
    if (same_file(&istat, &ostat)) {
	if (strequ(ifname, ofname)) {
	    fprintf(stderr, "%s: %s: cannot %scompress onto itself\n",
		    progname, ifname, decompress ? "de" : "");
	} else {
	    fprintf(stderr, "%s: %s and %s are the same file\n",
		    progname, ifname, ofname);
	}
	exit_code = ERROR;
	return ERROR;
    }
    /* Ask permission to overwrite the existing file */
    if (!force) {
#if 0
	char response[80];
	strcpy(response,"n");
	fprintf(stderr, "%s: %s already exists;", progname, ofname);
	if (foreground && isatty(fileno(stdin))) {
	    fprintf(stderr, " do you wish to overwrite (y or n)? ");
	    (void)fgets(response, sizeof(response)-1, stdin);
	}
	if (tolow(*response) != 'y') {
	    fprintf(stderr, "\tnot overwritten\n");
#endif
	    if (exit_code == OK) exit_code = WARNING;
	    return ERROR;
#if 0
	}
#endif
    }
    (void) chmod(ofname, 0777);
    if (unlink(ofname)) {
	fprintf(stderr, "%s: ", progname);
	perror(ofname);
	exit_code = ERROR;
	return ERROR;
    }
    return OK;
}


/* ========================================================================
 * Set the access and modification times from the given stat buffer.
 */
local void reset_times (name, statb)
    char *name;
    struct stat *statb;
{
    struct utimbuf	timep;

    /* Copy the time stamp */
    timep.actime  = statb->st_atime;
    timep.modtime = statb->st_mtime;

    /* Some systems (at least OS/2) do not support utime on directories */
    if (utime(name, &timep) && !S_ISDIR(statb->st_mode)) {
	WARN((stderr, "%s: ", progname));
	if (!quiet) perror(ofname);
    }
}


/* ========================================================================
 * Copy modes, times, ownership from input file to output file.
 * IN assertion: to_stdout is false.
 */
local void copy_stat(ifstat)
    struct stat *ifstat;
{
    if (decompress && time_stamp != 0 && ifstat->st_mtime != time_stamp) {
	ifstat->st_mtime = time_stamp;
	if (verbose > 1) {
	    fprintf(stderr, "%s: time stamp restored\n", ofname);
	}
    }
    reset_times(ofname, ifstat);

    /* Copy the protection modes */
    if (chmod(ofname, ifstat->st_mode & 07777)) {
	WARN((stderr, "%s: ", progname));
	if (!quiet) perror(ofname);
    }

    chown(ofname, ifstat->st_uid, ifstat->st_gid);  /* Copy ownership */

    remove_ofname = 0;
    /* It's now safe to remove the input file: */
    (void) chmod(ifname, 0777);
    if (unlink(ifname)) {
	WARN((stderr, "%s: ", progname));
	if (!quiet) perror(ifname);
    }
}

/* ========================================================================
 * Free all dynamically allocated variables and exit with the given code.
 */
local void do_exit(exitcode)
    int exitcode;
{
    static int in_exit = 0;

    if (in_exit) exit(exitcode);
    in_exit = 1;
    if (env != NULL)  free(env),  env  = NULL;
    if (args != NULL) free((char*)args), args = NULL;
    FREE(inbuf);
    FREE(outbuf);
    FREE(d_buf);
    FREE(window);
    FREE(tab_prefix);
    exit(exitcode);
}

/* ========================================================================
 * Signal and error handler.
 */
void abort_gzip()
{
   if (remove_ofname) {
       close(ofd);
       unlink (ofname);
   }
   do_exit(ERROR);
}
