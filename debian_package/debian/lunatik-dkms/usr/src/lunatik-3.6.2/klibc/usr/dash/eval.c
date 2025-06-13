/*-
 * Copyright (c) 1993
 *	The Regents of the University of California.  All rights reserved.
 * Copyright (c) 1997-2005
 *	Herbert Xu <herbert@gondor.apana.org.au>.  All rights reserved.
 *
 * This code is derived from software contributed to Berkeley by
 * Kenneth Almquist.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <sys/types.h>

/*
 * Evaluate a command.
 */

#include "shell.h"
#include "nodes.h"
#include "syntax.h"
#include "expand.h"
#include "parser.h"
#include "jobs.h"
#include "eval.h"
#include "builtins.h"
#include "options.h"
#include "exec.h"
#include "redir.h"
#include "input.h"
#include "output.h"
#include "trap.h"
#include "var.h"
#include "memalloc.h"
#include "error.h"
#include "show.h"
#include "mystring.h"
#ifndef SMALL
#include "myhistedit.h"
#endif


/* flags in argument to evaltree */
#define EV_EXIT 01		/* exit after evaluating tree */
#define EV_TESTED 02		/* exit status is checked; ignore -e flag */

int evalskip;			/* set if we are skipping commands */
STATIC int skipcount;		/* number of levels to skip */
MKINIT int loopnest;		/* current loop nesting level */
static int funcline;		/* starting line number of current function, or 0 if not in a function */


char *commandname;
int exitstatus;			/* exit status of last command */
int back_exitstatus;		/* exit status of backquoted command */


#if !defined(__alpha__) || (defined(__GNUC__) && __GNUC__ >= 3)
STATIC
#endif
void evaltreenr(union node *, int) __attribute__ ((__noreturn__));
STATIC void evalloop(union node *, int);
STATIC void evalfor(union node *, int);
STATIC void evalcase(union node *, int);
STATIC void evalsubshell(union node *, int);
STATIC void expredir(union node *);
STATIC void evalpipe(union node *, int);
#ifdef notyet
STATIC void evalcommand(union node *, int, struct backcmd *);
#else
STATIC void evalcommand(union node *, int);
#endif
STATIC int evalbltin(const struct builtincmd *, int, char **, int);
STATIC int evalfun(struct funcnode *, int, char **, int);
STATIC void prehash(union node *);
STATIC int eprintlist(struct output *, struct strlist *, int);
STATIC int bltincmd(int, char **);


STATIC const struct builtincmd bltin = {
	.name = nullstr,
	.builtin = bltincmd
};


/*
 * Called to reset things after an exception.
 */

#ifdef mkinit
INCLUDE "eval.h"

RESET {
	evalskip = 0;
	loopnest = 0;
}
#endif



/*
 * The eval commmand.
 */

static int evalcmd(int argc, char **argv, int flags)
{
        char *p;
        char *concat;
        char **ap;

        if (argc > 1) {
                p = argv[1];
                if (argc > 2) {
                        STARTSTACKSTR(concat);
                        ap = argv + 2;
                        for (;;) {
                        	concat = stputs(p, concat);
                                if ((p = *ap++) == NULL)
                                        break;
                                STPUTC(' ', concat);
                        }
                        STPUTC('\0', concat);
                        p = grabstackstr(concat);
                }
                return evalstring(p, flags & EV_TESTED);
        }
        return 0;
}


/*
 * Execute a command or commands contained in a string.
 */

int
evalstring(char *s, int flags)
{
	union node *n;
	struct stackmark smark;
	int status;

	setinputstring(s);
	setstackmark(&smark);

	status = 0;
	while ((n = parsecmd(0)) != NEOF) {
		evaltree(n, flags);
		status = exitstatus;
		popstackmark(&smark);
		if (evalskip)
			break;
	}
	popfile();

	return status;
}



/*
 * Evaluate a parse tree.  The value is left in the global variable
 * exitstatus.
 */

void
evaltree(union node *n, int flags)
{
	int checkexit = 0;
	void (*evalfn)(union node *, int);
	unsigned isor;
	int status;
	if (n == NULL) {
		TRACE(("evaltree(NULL) called\n"));
		goto out;
	}
#ifndef SMALL
	displayhist = 1;	/* show history substitutions done with fc */
#endif
	TRACE(("pid %d, evaltree(%p: %d, %d) called\n",
	    getpid(), n, n->type, flags));
	switch (n->type) {
	default:
#ifdef DEBUG
		out1fmt("Node type = %d\n", n->type);
#ifndef USE_GLIBC_STDIO
		flushout(out1);
#endif
		break;
#endif
	case NNOT:
		evaltree(n->nnot.com, EV_TESTED);
		status = !exitstatus;
		goto setstatus;
	case NREDIR:
		errlinno = lineno = n->nredir.linno;
		if (funcline)
			lineno -= funcline - 1;
		expredir(n->nredir.redirect);
		pushredir(n->nredir.redirect);
		status = redirectsafe(n->nredir.redirect, REDIR_PUSH);
		if (!status) {
			evaltree(n->nredir.n, flags & EV_TESTED);
			status = exitstatus;
		}
		if (n->nredir.redirect)
			popredir(0);
		goto setstatus;
	case NCMD:
#ifdef notyet
		if (eflag && !(flags & EV_TESTED))
			checkexit = ~0;
		evalcommand(n, flags, (struct backcmd *)NULL);
		break;
#else
		evalfn = evalcommand;
checkexit:
		if (eflag && !(flags & EV_TESTED))
			checkexit = ~0;
		goto calleval;
#endif
	case NFOR:
		evalfn = evalfor;
		goto calleval;
	case NWHILE:
	case NUNTIL:
		evalfn = evalloop;
		goto calleval;
	case NSUBSHELL:
	case NBACKGND:
		evalfn = evalsubshell;
		goto checkexit;
	case NPIPE:
		evalfn = evalpipe;
		goto checkexit;
	case NCASE:
		evalfn = evalcase;
		goto calleval;
	case NAND:
	case NOR:
	case NSEMI:
#if NAND + 1 != NOR
#error NAND + 1 != NOR
#endif
#if NOR + 1 != NSEMI
#error NOR + 1 != NSEMI
#endif
		isor = n->type - NAND;
		evaltree(
			n->nbinary.ch1,
			(flags | ((isor >> 1) - 1)) & EV_TESTED
		);
		if ((!exitstatus) == isor)
			break;
		if (!evalskip) {
			n = n->nbinary.ch2;
evaln:
			evalfn = evaltree;
calleval:
			evalfn(n, flags);
			break;
		}
		break;
	case NIF:
		evaltree(n->nif.test, EV_TESTED);
		if (evalskip)
			break;
		if (exitstatus == 0) {
			n = n->nif.ifpart;
			goto evaln;
		} else if (n->nif.elsepart) {
			n = n->nif.elsepart;
			goto evaln;
		}
		goto success;
	case NDEFUN:
		defun(n);
success:
		status = 0;
setstatus:
		exitstatus = status;
		break;
	}
out:
	if (checkexit & exitstatus)
		goto exexit;

	if (pendingsigs)
		dotrap();

	if (flags & EV_EXIT) {
exexit:
		exraise(EXEXIT);
	}
}


#if !defined(__alpha__) || (defined(__GNUC__) && __GNUC__ >= 3)
STATIC
#endif
void evaltreenr(union node *n, int flags)
#ifdef HAVE_ATTRIBUTE_ALIAS
	__attribute__ ((alias("evaltree")));
#else
{
	evaltree(n, flags);
	abort();
}
#endif


STATIC void
evalloop(union node *n, int flags)
{
	int status;

	loopnest++;
	status = 0;
	flags &= EV_TESTED;
	for (;;) {
		int i;

		evaltree(n->nbinary.ch1, EV_TESTED);
		if (evalskip) {
skipping:	  if (evalskip == SKIPCONT && --skipcount <= 0) {
				evalskip = 0;
				continue;
			}
			if (evalskip == SKIPBREAK && --skipcount <= 0)
				evalskip = 0;
			break;
		}
		i = exitstatus;
		if (n->type != NWHILE)
			i = !i;
		if (i != 0)
			break;
		evaltree(n->nbinary.ch2, flags);
		status = exitstatus;
		if (evalskip)
			goto skipping;
	}
	loopnest--;
	exitstatus = status;
}



STATIC void
evalfor(union node *n, int flags)
{
	struct arglist arglist;
	union node *argp;
	struct strlist *sp;
	struct stackmark smark;

	errlinno = lineno = n->nfor.linno;
	if (funcline)
		lineno -= funcline - 1;

	setstackmark(&smark);
	arglist.lastp = &arglist.list;
	for (argp = n->nfor.args ; argp ; argp = argp->narg.next) {
		expandarg(argp, &arglist, EXP_FULL | EXP_TILDE);
		/* XXX */
		if (evalskip)
			goto out;
	}
	*arglist.lastp = NULL;

	exitstatus = 0;
	loopnest++;
	flags &= EV_TESTED;
	for (sp = arglist.list ; sp ; sp = sp->next) {
		setvar(n->nfor.var, sp->text, 0);
		evaltree(n->nfor.body, flags);
		if (evalskip) {
			if (evalskip == SKIPCONT && --skipcount <= 0) {
				evalskip = 0;
				continue;
			}
			if (evalskip == SKIPBREAK && --skipcount <= 0)
				evalskip = 0;
			break;
		}
	}
	loopnest--;
out:
	popstackmark(&smark);
}



STATIC void
evalcase(union node *n, int flags)
{
	union node *cp;
	union node *patp;
	struct arglist arglist;
	struct stackmark smark;

	errlinno = lineno = n->ncase.linno;
	if (funcline)
		lineno -= funcline - 1;

	setstackmark(&smark);
	arglist.lastp = &arglist.list;
	expandarg(n->ncase.expr, &arglist, EXP_TILDE);
	exitstatus = 0;
	for (cp = n->ncase.cases ; cp && evalskip == 0 ; cp = cp->nclist.next) {
		for (patp = cp->nclist.pattern ; patp ; patp = patp->narg.next) {
			if (casematch(patp, arglist.list->text)) {
				if (evalskip == 0) {
					evaltree(cp->nclist.body, flags);
				}
				goto out;
			}
		}
	}
out:
	popstackmark(&smark);
}



/*
 * Kick off a subshell to evaluate a tree.
 */

STATIC void
evalsubshell(union node *n, int flags)
{
	struct job *jp;
	int backgnd = (n->type == NBACKGND);
	int status;

	errlinno = lineno = n->nredir.linno;
	if (funcline)
		lineno -= funcline - 1;

	expredir(n->nredir.redirect);
	if (!backgnd && flags & EV_EXIT && !have_traps())
		goto nofork;
	INTOFF;
	jp = makejob(n, 1);
	if (forkshell(jp, n, backgnd) == 0) {
		INTON;
		flags |= EV_EXIT;
		if (backgnd)
			flags &=~ EV_TESTED;
nofork:
		redirect(n->nredir.redirect, 0);
		evaltreenr(n->nredir.n, flags);
		/* never returns */
	}
	status = 0;
	if (! backgnd)
		status = waitforjob(jp);
	exitstatus = status;
	INTON;
}



/*
 * Compute the names of the files in a redirection list.
 */

STATIC void
expredir(union node *n)
{
	union node *redir;

	for (redir = n ; redir ; redir = redir->nfile.next) {
		struct arglist fn;
		fn.lastp = &fn.list;
		switch (redir->type) {
		case NFROMTO:
		case NFROM:
		case NTO:
		case NCLOBBER:
		case NAPPEND:
			expandarg(redir->nfile.fname, &fn, EXP_TILDE | EXP_REDIR);
			redir->nfile.expfname = fn.list->text;
			break;
		case NFROMFD:
		case NTOFD:
			if (redir->ndup.vname) {
				expandarg(redir->ndup.vname, &fn, EXP_FULL | EXP_TILDE);
				fixredir(redir, fn.list->text, 1);
			}
			break;
		}
	}
}



/*
 * Evaluate a pipeline.  All the processes in the pipeline are children
 * of the process creating the pipeline.  (This differs from some versions
 * of the shell, which make the last process in a pipeline the parent
 * of all the rest.)
 */

STATIC void
evalpipe(union node *n, int flags)
{
	struct job *jp;
	struct nodelist *lp;
	int pipelen;
	int prevfd;
	int pip[2];

	TRACE(("evalpipe(0x%lx) called\n", (long)n));
	pipelen = 0;
	for (lp = n->npipe.cmdlist ; lp ; lp = lp->next)
		pipelen++;
	flags |= EV_EXIT;
	INTOFF;
	jp = makejob(n, pipelen);
	prevfd = -1;
	for (lp = n->npipe.cmdlist ; lp ; lp = lp->next) {
		prehash(lp->n);
		pip[1] = -1;
		if (lp->next) {
			if (pipe(pip) < 0) {
				close(prevfd);
				sh_error("Pipe call failed");
			}
		}
		if (forkshell(jp, lp->n, n->npipe.backgnd) == 0) {
			INTON;
			if (pip[1] >= 0) {
				close(pip[0]);
			}
			if (prevfd > 0) {
				dup2(prevfd, 0);
				close(prevfd);
			}
			if (pip[1] > 1) {
				dup2(pip[1], 1);
				close(pip[1]);
			}
			evaltreenr(lp->n, flags);
			/* never returns */
		}
		if (prevfd >= 0)
			close(prevfd);
		prevfd = pip[0];
		close(pip[1]);
	}
	if (n->npipe.backgnd == 0) {
		exitstatus = waitforjob(jp);
		TRACE(("evalpipe:  job done exit status %d\n", exitstatus));
	}
	INTON;
}



/*
 * Execute a command inside back quotes.  If it's a builtin command, we
 * want to save its output in a block obtained from malloc.  Otherwise
 * we fork off a subprocess and get the output of the command via a pipe.
 * Should be called with interrupts off.
 */

void
evalbackcmd(union node *n, struct backcmd *result)
{
	int pip[2];
	struct job *jp;

	result->fd = -1;
	result->buf = NULL;
	result->nleft = 0;
	result->jp = NULL;
	if (n == NULL) {
		goto out;
	}

	if (pipe(pip) < 0)
		sh_error("Pipe call failed");
	jp = makejob(n, 1);
	if (forkshell(jp, n, FORK_NOJOB) == 0) {
		FORCEINTON;
		close(pip[0]);
		if (pip[1] != 1) {
			dup2(pip[1], 1);
			close(pip[1]);
		}
		ifsfree();
		evaltreenr(n, EV_EXIT);
		/* NOTREACHED */
	}
	close(pip[1]);
	result->fd = pip[0];
	result->jp = jp;

out:
	TRACE(("evalbackcmd done: fd=%d buf=0x%x nleft=%d jp=0x%x\n",
		result->fd, result->buf, result->nleft, result->jp));
}

static char **
parse_command_args(char **argv, const char **path)
{
	char *cp, c;

	for (;;) {
		cp = *++argv;
		if (!cp)
			return 0;
		if (*cp++ != '-')
			break;
		if (!(c = *cp++))
			break;
		if (c == '-' && !*cp) {
			if (!*++argv)
				return 0;
			break;
		}
		do {
			switch (c) {
			case 'p':
				*path = defpath;
				break;
			default:
				/* run 'typecmd' for other options */
				return 0;
			}
		} while ((c = *cp++));
	}
	return argv;
}



/*
 * Execute a simple command.
 */

STATIC void
#ifdef notyet
evalcommand(union node *cmd, int flags, struct backcmd *backcmd)
#else
evalcommand(union node *cmd, int flags)
#endif
{
	struct localvar_list *localvar_stop;
	struct redirtab *redir_stop;
	struct stackmark smark;
	union node *argp;
	struct arglist arglist;
	struct arglist varlist;
	char **argv;
	int argc;
	struct strlist *sp;
#ifdef notyet
	int pip[2];
#endif
	struct cmdentry cmdentry;
	struct job *jp;
	char *lastarg;
	const char *path;
	int spclbltin;
	int execcmd;
	int status;
	char **nargv;

	errlinno = lineno = cmd->ncmd.linno;
	if (funcline)
		lineno -= funcline - 1;

	/* First expand the arguments. */
	TRACE(("evalcommand(0x%lx, %d) called\n", (long)cmd, flags));
	setstackmark(&smark);
	localvar_stop = pushlocalvars();
	back_exitstatus = 0;

	cmdentry.cmdtype = CMDBUILTIN;
	cmdentry.u.cmd = &bltin;
	varlist.lastp = &varlist.list;
	*varlist.lastp = NULL;
	arglist.lastp = &arglist.list;
	*arglist.lastp = NULL;

	argc = 0;
	for (argp = cmd->ncmd.args; argp; argp = argp->narg.next) {
		struct strlist **spp;

		spp = arglist.lastp;
		expandarg(argp, &arglist, EXP_FULL | EXP_TILDE);
		for (sp = *spp; sp; sp = sp->next)
			argc++;
	}

	/* Reserve one extra spot at the front for shellexec. */
	nargv = stalloc(sizeof (char *) * (argc + 2));
	argv = ++nargv;
	for (sp = arglist.list ; sp ; sp = sp->next) {
		TRACE(("evalcommand arg: %s\n", sp->text));
		*nargv++ = sp->text;
	}
	*nargv = NULL;

	lastarg = NULL;
	if (iflag && funcline == 0 && argc > 0)
		lastarg = nargv[-1];

	preverrout.fd = 2;
	expredir(cmd->ncmd.redirect);
	redir_stop = pushredir(cmd->ncmd.redirect);
	status = redirectsafe(cmd->ncmd.redirect, REDIR_PUSH|REDIR_SAVEFD2);

	path = vpath.text;
	for (argp = cmd->ncmd.assign; argp; argp = argp->narg.next) {
		struct strlist **spp;
		char *p;

		spp = varlist.lastp;
		expandarg(argp, &varlist, EXP_VARTILDE);

		mklocal((*spp)->text);

		/*
		 * Modify the command lookup path, if a PATH= assignment
		 * is present
		 */
		p = (*spp)->text;
		if (varequal(p, path))
			path = p;
	}

	/* Print the command if xflag is set. */
	if (xflag) {
		struct output *out;
		int sep;

		out = &preverrout;
		outstr(expandstr(ps4val()), out);
		sep = 0;
		sep = eprintlist(out, varlist.list, sep);
		eprintlist(out, arglist.list, sep);
		outcslow('\n', out);
#ifdef FLUSHERR
		flushout(out);
#endif
	}

	execcmd = 0;
	spclbltin = -1;

	/* Now locate the command. */
	if (argc) {
		const char *oldpath;
		int cmd_flag = DO_ERR;

		path += 5;
		oldpath = path;
		for (;;) {
			find_command(argv[0], &cmdentry, cmd_flag, path);
			if (cmdentry.cmdtype == CMDUNKNOWN) {
				status = 127;
#ifdef FLUSHERR
				flushout(&errout);
#endif
				goto bail;
			}

			/* implement bltin and command here */
			if (cmdentry.cmdtype != CMDBUILTIN)
				break;
			if (spclbltin < 0)
				spclbltin =
					cmdentry.u.cmd->flags &
					BUILTIN_SPECIAL
				;
			if (cmdentry.u.cmd == EXECCMD)
				execcmd++;
			if (cmdentry.u.cmd != COMMANDCMD)
				break;

			path = oldpath;
			nargv = parse_command_args(argv, &path);
			if (!nargv)
				break;
			argc -= nargv - argv;
			argv = nargv;
			cmd_flag |= DO_NOFUNC;
		}
	}

	if (status) {
bail:
		exitstatus = status;

		/* We have a redirection error. */
		if (spclbltin > 0)
			exraise(EXERROR);

		goto out;
	}

	/* Execute the command. */
	switch (cmdentry.cmdtype) {
	default:
		/* Fork off a child process if necessary. */
		if (!(flags & EV_EXIT) || have_traps()) {
			INTOFF;
			jp = makejob(cmd, 1);
			if (forkshell(jp, cmd, FORK_FG) != 0) {
				exitstatus = waitforjob(jp);
				INTON;
				break;
			}
			FORCEINTON;
		}
		listsetvar(varlist.list, VEXPORT|VSTACK);
		shellexec(argv, path, cmdentry.u.index);
		/* NOTREACHED */

	case CMDBUILTIN:
		if (spclbltin > 0 || argc == 0) {
			poplocalvars(1);
			if (execcmd && argc > 1)
				listsetvar(varlist.list, VEXPORT);
		}
		if (evalbltin(cmdentry.u.cmd, argc, argv, flags)) {
			int status;
			int i;

			i = exception;
			if (i == EXEXIT)
				goto raise;

			status = (i == EXINT) ? SIGINT + 128 : 2;
			exitstatus = status;

			if (i == EXINT || spclbltin > 0) {
raise:
				longjmp(handler->loc, 1);
			}
			FORCEINTON;
		}
		break;

	case CMDFUNCTION:
		poplocalvars(1);
		if (evalfun(cmdentry.u.func, argc, argv, flags))
			goto raise;
		break;
	}

out:
	if (cmd->ncmd.redirect)
		popredir(execcmd);
	unwindredir(redir_stop);
	unwindlocalvars(localvar_stop);
	if (lastarg)
		/* dsl: I think this is intended to be used to support
		 * '_' in 'vi' command mode during line editing...
		 * However I implemented that within libedit itself.
		 */
		setvar("_", lastarg, 0);
	popstackmark(&smark);
}

STATIC int
evalbltin(const struct builtincmd *cmd, int argc, char **argv, int flags)
{
	char *volatile savecmdname;
	struct jmploc *volatile savehandler;
	struct jmploc jmploc;
	int status;
	int i;

	savecmdname = commandname;
	savehandler = handler;
	if ((i = setjmp(jmploc.loc)))
		goto cmddone;
	handler = &jmploc;
	commandname = argv[0];
	argptr = argv + 1;
	optptr = NULL;			/* initialize nextopt */
	if (cmd == EVALCMD)
		status = evalcmd(argc, argv, flags);
	else
		status = (*cmd->builtin)(argc, argv);
	flushall();
	status |= outerr(out1);
	exitstatus = status;
cmddone:
	freestdout();
	commandname = savecmdname;
	handler = savehandler;

	return i;
}

STATIC int
evalfun(struct funcnode *func, int argc, char **argv, int flags)
{
	volatile struct shparam saveparam;
	struct jmploc *volatile savehandler;
	struct jmploc jmploc;
	int e;
	int savefuncline;

	saveparam = shellparam;
	savefuncline = funcline;
	savehandler = handler;
	if ((e = setjmp(jmploc.loc))) {
		goto funcdone;
	}
	INTOFF;
	handler = &jmploc;
	shellparam.malloc = 0;
	func->count++;
	funcline = func->n.ndefun.linno;
	INTON;
	shellparam.nparam = argc - 1;
	shellparam.p = argv + 1;
	shellparam.optind = 1;
	shellparam.optoff = -1;
	pushlocalvars();
	evaltree(func->n.ndefun.body, flags & EV_TESTED);
	poplocalvars(0);
funcdone:
	INTOFF;
	funcline = savefuncline;
	freefunc(func);
	freeparam(&shellparam);
	shellparam = saveparam;
	handler = savehandler;
	INTON;
	evalskip &= ~SKIPFUNC;
	return e;
}


/*
 * Search for a command.  This is called before we fork so that the
 * location of the command will be available in the parent as well as
 * the child.  The check for "goodname" is an overly conservative
 * check that the name will not be subject to expansion.
 */

STATIC void
prehash(union node *n)
{
	struct cmdentry entry;

	if (n->type == NCMD && n->ncmd.args)
		if (goodname(n->ncmd.args->narg.text))
			find_command(n->ncmd.args->narg.text, &entry, 0,
				     pathval());
}



/*
 * Builtin commands.  Builtin commands whose functions are closely
 * tied to evaluation are implemented here.
 */

/*
 * No command given.
 */

STATIC int
bltincmd(int argc, char **argv)
{
	/*
	 * Preserve exitstatus of a previous possible redirection
	 * as POSIX mandates
	 */
	return back_exitstatus;
}


/*
 * Handle break and continue commands.  Break, continue, and return are
 * all handled by setting the evalskip flag.  The evaluation routines
 * above all check this flag, and if it is set they start skipping
 * commands rather than executing them.  The variable skipcount is
 * the number of loops to break/continue, or the number of function
 * levels to return.  (The latter is always 1.)  It should probably
 * be an error to break out of more loops than exist, but it isn't
 * in the standard shell so we don't make it one here.
 */

int
breakcmd(int argc, char **argv)
{
	int n = argc > 1 ? number(argv[1]) : 1;

	if (n <= 0)
		badnum(argv[1]);
	if (n > loopnest)
		n = loopnest;
	if (n > 0) {
		evalskip = (**argv == 'c')? SKIPCONT : SKIPBREAK;
		skipcount = n;
	}
	return 0;
}


/*
 * The return command.
 */

int
returncmd(int argc, char **argv)
{
	/*
	 * If called outside a function, do what ksh does;
	 * skip the rest of the file.
	 */
	evalskip = SKIPFUNC;
	return argv[1] ? number(argv[1]) : exitstatus;
}


int
falsecmd(int argc, char **argv)
{
	return 1;
}


int
truecmd(int argc, char **argv)
{
	return 0;
}


int
execcmd(int argc, char **argv)
{
	if (argc > 1) {
		iflag = 0;		/* exit on error */
		mflag = 0;
		optschanged();
		shellexec(argv + 1, pathval(), 0);
	}
	return 0;
}


STATIC int
eprintlist(struct output *out, struct strlist *sp, int sep)
{
	while (sp) {
		const char *p;

		p = " %s";
		p += (1 - sep);
		sep |= 1;
		outfmt(out, p, sp->text);
		sp = sp->next;
	}

	return sep;
}
