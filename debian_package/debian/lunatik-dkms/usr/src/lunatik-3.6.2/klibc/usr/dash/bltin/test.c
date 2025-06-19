/*
 * test(1); version 7-like  --  author Erik Baalbergen
 * modified by Eric Gisin to be used as built-in.
 * modified by Arnold Robbins to add SVR3 compatibility
 * (-x -c -b -p -u -g -k) plus Korn's -L -nt -ot -ef and new -S (socket).
 * modified by J.T. Conklin for NetBSD.
 *
 * This program is in the Public Domain.
 */

#include <sys/stat.h>
#include <sys/types.h>

#include <fcntl.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include "bltin.h"

/* test(1) accepts the following grammar:
	oexpr	::= aexpr | aexpr "-o" oexpr ;
	aexpr	::= nexpr | nexpr "-a" aexpr ;
	nexpr	::= primary | "!" primary
	primary	::= unary-operator operand
		| operand binary-operator operand
		| operand
		| "(" oexpr ")"
		;
	unary-operator ::= "-r"|"-w"|"-x"|"-f"|"-d"|"-c"|"-b"|"-p"|
		"-u"|"-g"|"-k"|"-s"|"-t"|"-z"|"-n"|"-o"|"-O"|"-G"|"-L"|"-S";

	binary-operator ::= "="|"!="|"-eq"|"-ne"|"-ge"|"-gt"|"-le"|"-lt"|
			"-nt"|"-ot"|"-ef";
	operand ::= <any legal UNIX file name>
*/

enum token {
	EOI,
	FILRD,
	FILWR,
	FILEX,
	FILEXIST,
	FILREG,
	FILDIR,
	FILCDEV,
	FILBDEV,
	FILFIFO,
	FILSOCK,
	FILSYM,
	FILGZ,
	FILTT,
	FILSUID,
	FILSGID,
	FILSTCK,
	FILNT,
	FILOT,
	FILEQ,
	FILUID,
	FILGID,
	STREZ,
	STRNZ,
	STREQ,
	STRNE,
	STRLT,
	STRGT,
	INTEQ,
	INTNE,
	INTGE,
	INTGT,
	INTLE,
	INTLT,
	UNOT,
	BAND,
	BOR,
	LPAREN,
	RPAREN,
	OPERAND
};

enum token_types {
	UNOP,
	BINOP,
	BUNOP,
	BBINOP,
	PAREN
};

static struct t_op {
	const char *op_text;
	short op_num, op_type;
} const ops [] = {
	{"-r",	FILRD,	UNOP},
	{"-w",	FILWR,	UNOP},
	{"-x",	FILEX,	UNOP},
	{"-e",	FILEXIST,UNOP},
	{"-f",	FILREG,	UNOP},
	{"-d",	FILDIR,	UNOP},
	{"-c",	FILCDEV,UNOP},
	{"-b",	FILBDEV,UNOP},
	{"-p",	FILFIFO,UNOP},
	{"-u",	FILSUID,UNOP},
	{"-g",	FILSGID,UNOP},
	{"-k",	FILSTCK,UNOP},
	{"-s",	FILGZ,	UNOP},
	{"-t",	FILTT,	UNOP},
	{"-z",	STREZ,	UNOP},
	{"-n",	STRNZ,	UNOP},
	{"-h",	FILSYM,	UNOP},		/* for backwards compat */
	{"-O",	FILUID,	UNOP},
	{"-G",	FILGID,	UNOP},
	{"-L",	FILSYM,	UNOP},
	{"-S",	FILSOCK,UNOP},
	{"=",	STREQ,	BINOP},
	{"!=",	STRNE,	BINOP},
	{"<",	STRLT,	BINOP},
	{">",	STRGT,	BINOP},
	{"-eq",	INTEQ,	BINOP},
	{"-ne",	INTNE,	BINOP},
	{"-ge",	INTGE,	BINOP},
	{"-gt",	INTGT,	BINOP},
	{"-le",	INTLE,	BINOP},
	{"-lt",	INTLT,	BINOP},
	{"-nt",	FILNT,	BINOP},
	{"-ot",	FILOT,	BINOP},
	{"-ef",	FILEQ,	BINOP},
	{"!",	UNOT,	BUNOP},
	{"-a",	BAND,	BBINOP},
	{"-o",	BOR,	BBINOP},
	{"(",	LPAREN,	PAREN},
	{")",	RPAREN,	PAREN},
	{0,	0,	0}
};

static char **t_wp;
static struct t_op const *t_wp_op;

static void syntax(const char *, const char *);
static int oexpr(enum token);
static int aexpr(enum token);
static int nexpr(enum token);
static int primary(enum token);
static int binop(void);
static int filstat(char *, enum token);
static enum token t_lex(char **);
static int isoperand(char **);
static int newerf(const char *, const char *);
static int olderf(const char *, const char *);
static int equalf(const char *, const char *);
#ifdef HAVE_FACCESSAT
static int test_file_access(const char *, int);
#else
static int test_st_mode(const struct stat64 *, int);
static int bash_group_member(gid_t);
#endif

static inline intmax_t getn(const char *s)
{
	return atomax10(s);
}

static const struct t_op *getop(const char *s)
{
	const struct t_op *op;

	for (op = ops; op->op_text; op++) {
		if (strcmp(s, op->op_text) == 0)
			return op;
	}

	return NULL;
}

int
testcmd(int argc, char **argv)
{
	const struct t_op *op;
	enum token n;
	int res;

	if (*argv[0] == '[') {
		if (*argv[--argc] != ']')
			error("missing ]");
		argv[argc] = NULL;
	}

	argv++;
	argc--;

	if (argc < 1)
		return 1;

	/*
	 * POSIX prescriptions: he who wrote this deserves the Nobel
	 * peace prize.
	 */
	switch (argc) {
	case 3:
		op = getop(argv[1]);
		if (op && op->op_type == BINOP) {
			n = OPERAND;
			goto eval;
		}
		/* fall through */

	case 4:
		if (!strcmp(argv[0], "(") && !strcmp(argv[argc - 1], ")")) {
			argv[--argc] = NULL;
			argv++;
			argc--;
		}
	}

	n = t_lex(argv);

eval:
	t_wp = argv;
	res = !oexpr(n);
	argv = t_wp;

	if (argv[0] != NULL && argv[1] != NULL)
		syntax(argv[0], "unexpected operator");

	return res;
}

static void
syntax(const char *op, const char *msg)
{
	if (op && *op)
		error("%s: %s", op, msg);
	else
		error("%s", msg);
}

static int
oexpr(enum token n)
{
	int res = 0;

	for (;;) {
		res |= aexpr(n);
		n = t_lex(t_wp + 1);
		if (n != BOR)
			break;
		n = t_lex(t_wp += 2);
	}
	return res;
}

static int
aexpr(enum token n)
{
	int res = 1;

	for (;;) {
		if (!nexpr(n))
			res = 0;
		n = t_lex(t_wp + 1);
		if (n != BAND)
			break;
		n = t_lex(t_wp += 2);
	}
	return res;
}

static int
nexpr(enum token n)
{
	if (n == UNOT)
		return !nexpr(t_lex(++t_wp));
	return primary(n);
}

static int
primary(enum token n)
{
	enum token nn;
	int res;

	if (n == EOI)
		return 0;		/* missing expression */
	if (n == LPAREN) {
		if ((nn = t_lex(++t_wp)) == RPAREN)
			return 0;	/* missing expression */
		res = oexpr(nn);
		if (t_lex(++t_wp) != RPAREN)
			syntax(NULL, "closing paren expected");
		return res;
	}
	if (t_wp_op && t_wp_op->op_type == UNOP) {
		/* unary expression */
		if (*++t_wp == NULL)
			syntax(t_wp_op->op_text, "argument expected");
		switch (n) {
		case STREZ:
			return strlen(*t_wp) == 0;
		case STRNZ:
			return strlen(*t_wp) != 0;
		case FILTT:
			return isatty(getn(*t_wp));
#ifdef HAVE_FACCESSAT
		case FILRD:
			return test_file_access(*t_wp, R_OK);
		case FILWR:
			return test_file_access(*t_wp, W_OK);
		case FILEX:
			return test_file_access(*t_wp, X_OK);
#endif
		default:
			return filstat(*t_wp, n);
		}
	}

	if (t_lex(t_wp + 1), t_wp_op && t_wp_op->op_type == BINOP) {
		return binop();
	}

	return strlen(*t_wp) > 0;
}

static int
binop(void)
{
	const char *opnd1, *opnd2;
	struct t_op const *op;

	opnd1 = *t_wp;
	(void) t_lex(++t_wp);
	op = t_wp_op;

	if ((opnd2 = *++t_wp) == (char *)0)
		syntax(op->op_text, "argument expected");

	switch (op->op_num) {
	default:
#ifdef DEBUG
		abort();
		/* NOTREACHED */
#endif
	case STREQ:
		return strcmp(opnd1, opnd2) == 0;
	case STRNE:
		return strcmp(opnd1, opnd2) != 0;
	case STRLT:
		return strcmp(opnd1, opnd2) < 0;
	case STRGT:
		return strcmp(opnd1, opnd2) > 0;
	case INTEQ:
		return getn(opnd1) == getn(opnd2);
	case INTNE:
		return getn(opnd1) != getn(opnd2);
	case INTGE:
		return getn(opnd1) >= getn(opnd2);
	case INTGT:
		return getn(opnd1) > getn(opnd2);
	case INTLE:
		return getn(opnd1) <= getn(opnd2);
	case INTLT:
		return getn(opnd1) < getn(opnd2);
	case FILNT:
		return newerf (opnd1, opnd2);
	case FILOT:
		return olderf (opnd1, opnd2);
	case FILEQ:
		return equalf (opnd1, opnd2);
	}
}

static int
filstat(char *nm, enum token mode)
{
	struct stat64 s;

	if (mode == FILSYM ? lstat64(nm, &s) : stat64(nm, &s))
		return 0;

	switch (mode) {
#ifndef HAVE_FACCESSAT
	case FILRD:
		return test_st_mode(&s, R_OK);
	case FILWR:
		return test_st_mode(&s, W_OK);
	case FILEX:
		return test_st_mode(&s, X_OK);
#endif
	case FILEXIST:
		return 1;
	case FILREG:
		return S_ISREG(s.st_mode);
	case FILDIR:
		return S_ISDIR(s.st_mode);
	case FILCDEV:
		return S_ISCHR(s.st_mode);
	case FILBDEV:
		return S_ISBLK(s.st_mode);
	case FILFIFO:
		return S_ISFIFO(s.st_mode);
	case FILSOCK:
		return S_ISSOCK(s.st_mode);
	case FILSYM:
		return S_ISLNK(s.st_mode);
	case FILSUID:
		return (s.st_mode & S_ISUID) != 0;
	case FILSGID:
		return (s.st_mode & S_ISGID) != 0;
	case FILSTCK:
		return (s.st_mode & S_ISVTX) != 0;
	case FILGZ:
		return !!s.st_size;
	case FILUID:
		return s.st_uid == geteuid();
	case FILGID:
		return s.st_gid == getegid();
	default:
		return 1;
	}
}

static enum token t_lex(char **tp)
{
	struct t_op const *op;
	char *s = *tp;

	if (s == 0) {
		t_wp_op = (struct t_op *)0;
		return EOI;
	}

	op = getop(s);
	if (op && !(op->op_type == UNOP && isoperand(tp)) &&
	    !(op->op_num == LPAREN && !tp[1])) {
		t_wp_op = op;
		return op->op_num;
	}

	t_wp_op = (struct t_op *)0;
	return OPERAND;
}

static int isoperand(char **tp)
{
	struct t_op const *op;
	char *s;

	if (!(s = tp[1]))
		return 1;
	if (!tp[2])
		return 0;

	op = getop(s);
	return op && op->op_type == BINOP;
}

static int
newerf (const char *f1, const char *f2)
{
	struct stat b1, b2;

	return (stat (f1, &b1) == 0 &&
		stat (f2, &b2) == 0 &&
		b1.st_mtime > b2.st_mtime);
}

static int
olderf (const char *f1, const char *f2)
{
	struct stat b1, b2;

	return (stat (f1, &b1) == 0 &&
		stat (f2, &b2) == 0 &&
		b1.st_mtime < b2.st_mtime);
}

static int
equalf (const char *f1, const char *f2)
{
	struct stat b1, b2;

	return (stat (f1, &b1) == 0 &&
		stat (f2, &b2) == 0 &&
		b1.st_dev == b2.st_dev &&
		b1.st_ino == b2.st_ino);
}

#ifdef HAVE_FACCESSAT
static int test_file_access(const char *path, int mode)
{
	return !faccessat(AT_FDCWD, path, mode, AT_EACCESS);
}
#else	/* HAVE_FACCESSAT */
/*
 * Similar to what access(2) does, but uses the effective uid and gid.
 * Doesn't make the mistake of telling root that any file is executable.
 * Returns non-zero if the file is accessible.
 */
static int
test_st_mode(const struct stat64 *st, int mode)
{
	int euid = geteuid();

	if (euid == 0) {
		/* Root can read or write any file. */
		if (mode != X_OK)
			return 1;

		/* Root can execute any file that has any one of the execute
		   bits set. */
		mode = S_IXUSR | S_IXGRP | S_IXOTH;
	} else if (st->st_uid == euid)
		mode <<= 6;
	else if (bash_group_member(st->st_gid))
		mode <<= 3;

	return st->st_mode & mode;
}

/* Return non-zero if GID is one that we have in our groups list. */
static int
bash_group_member(gid_t gid)
{
	register int i;
	gid_t *group_array;
	int ngroups;

	/* Short-circuit if possible, maybe saving a call to getgroups(). */
	if (gid == getgid() || gid == getegid())
		return (1);

	ngroups = getgroups(0, NULL);
	group_array = stalloc(ngroups * sizeof(gid_t));
	if ((getgroups(ngroups, group_array)) != ngroups)
		return (0);

	/* Search through the list looking for GID. */
	for (i = 0; i < ngroups; i++)
		if (gid == group_array[i])
			return (1);

	return (0);
}
#endif	/* HAVE_FACCESSAT */
