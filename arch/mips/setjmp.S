/*	$NetBSD: locore.S,v 1.208 2016/11/09 11:50:09 maya Exp $	*/

/*
 * Copyright (c) 2017-2019 CUJO LLC.
 * Copyright (c) 1992, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * This code is derived from software contributed to Berkeley by
 * Digital Equipment Corporation and Ralph Campbell.
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
 *
 * Copyright (C) 1989 Digital Equipment Corporation.
 * Permission to use, copy, modify, and distribute this software and
 * its documentation for any purpose and without fee is hereby granted,
 * provided that the above copyright notice appears in all copies.
 * Digital Equipment Corporation makes no representations about the
 * suitability of this software for any purpose.  It is provided "as is"
 * without express or implied warranty.
 *
 * from: Header: /sprite/src/kernel/mach/ds3100.md/RCS/loMem.s,
 *	v 1.1 89/07/11 17:55:04 nelson Exp  SPRITE (DECWRL)
 * from: Header: /sprite/src/kernel/mach/ds3100.md/RCS/machAsm.s,
 *	v 9.2 90/01/29 18:00:39 shirriff Exp  SPRITE (DECWRL)
 * from: Header: /sprite/src/kernel/vm/ds3100.md/vmPmaxAsm.s,
 *	v 1.1 89/07/10 14:27:41 nelson Exp  SPRITE (DECWRL)
 *
 *	@(#)locore.s	8.5 (Berkeley) 1/4/94
 */

#define _C_LABEL(x) x

#include "asm.h"
#include "regdef.h"

/* cpuregs.h */
#define MIPS_COP_0_STATUS t0
#define COP0_SYNC nop

#define SF_REG_S0
#define SF_REG_S1 8
#define SF_REG_S2 16
#define SF_REG_S3 24
#define SF_REG_S4 32
#define SF_REG_S5 40
#define SF_REG_S6 48
#define SF_REG_S7 56
#if defined(__mips_n32) || defined(__mips_n64)
#define SF_REG_GP 64
#define SF_REG_SP 72
#define SF_REG_S8 80
#define SF_REG_RA 88
#define SF_REG_SR 96
#else
#define SF_REG_SP 64
#define SF_REG_S8 72
#define SF_REG_RA 80
#define SF_REG_SR 88
#endif

.text
.set noreorder

/*
 * setjmp(label_t *)
 * longjmp(label_t *)
 */
LEAF(setjmp)
	mfc0	v0, MIPS_COP_0_STATUS
	REG_PROLOGUE
	REG_S	s0, SF_REG_S0(a0)
	REG_S	s1, SF_REG_S1(a0)
	REG_S	s2, SF_REG_S2(a0)
	REG_S	s3, SF_REG_S3(a0)
	REG_S	s4, SF_REG_S4(a0)
	REG_S	s5, SF_REG_S5(a0)
	REG_S	s6, SF_REG_S6(a0)
	REG_S	s7, SF_REG_S7(a0)
	#REG_S	t8, SF_REG_T8(a0)		# no reason to save MIPS_CURLWP
#if defined(__mips_n32) || defined(__mips_n64)
	REG_S	gp, SF_REG_GP(a0)
#endif
	REG_S	sp, SF_REG_SP(a0)
	REG_S	s8, SF_REG_S8(a0)
	REG_S	ra, SF_REG_RA(a0)
	REG_S	v0, SF_REG_SR(a0)
	REG_EPILOGUE
	jr	ra
	move	v0, zero
END(setjmp)

LEAF(longjmp)
	REG_PROLOGUE
	REG_L	v0, SF_REG_SR(a0)
	DYNAMIC_STATUS_MASK(v0,ra)		# machine dependent masking
	REG_L	ra, SF_REG_RA(a0)
	REG_L	s0, SF_REG_S0(a0)
	REG_L	s1, SF_REG_S1(a0)
	REG_L	s2, SF_REG_S2(a0)
	REG_L	s3, SF_REG_S3(a0)
	REG_L	s4, SF_REG_S4(a0)
	REG_L	s5, SF_REG_S5(a0)
	REG_L	s6, SF_REG_S6(a0)
	REG_L	s7, SF_REG_S7(a0)
	#REG_L	t8, SF_REG_T8(a0)		# no reason to load MIPS_CURLWP
#if defined(__mips_n32) || defined(__mips_n64)
	REG_L	gp, SF_REG_GP(a0)
#endif
	REG_L	sp, SF_REG_SP(a0)
	REG_L	s8, SF_REG_S8(a0)
	REG_EPILOGUE
	mtc0	v0, MIPS_COP_0_STATUS
	COP0_SYNC
	jr	ra
	 li	v0, 1
END(longjmp)
