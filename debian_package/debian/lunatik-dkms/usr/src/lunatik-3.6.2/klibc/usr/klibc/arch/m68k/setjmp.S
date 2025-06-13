#
# arch/m68k/setjmp.S
#
# setjmp/longjmp for the m68k architecture
#

#
# The jmp_buf is assumed to contain the following, in order:
#	%d2..%d7
#	%a2..%a7
#	return address
#

	.text
	.align 2
	.globl setjmp
	.type setjmp, @function
setjmp:
	move.l	(%sp)+, %d0		| Return address
	movea.l	(%sp), %a0		| Buffer address
	| Postincrement mode is not permitted here...
	movem.l	%d2-%d7/%a2-%a7, (%a0)
	move.l	%d0, 48(%a0)		| Return address
	move.l	%d0, -(%sp)		| Restore return address
	clr.l	%d0			| Return value
	movea.l	%d0, %a0		| Redundant return...
	rts

	.size setjmp,.-setjmp

	.text
	.align 2
	.globl longjmp
	.type longjmp, @function
longjmp:
	move.l	4(%sp), %a0		| Buffer address
	move.l	8(%sp), %d0		| Return value
	movem.l	(%a0)+, %d2-%d7/%a2-%a7
	movea.l	(%a0), %a1
	movea.l	%d0, %a0		| Redundant return...
	jmp.l	(%a1)

	.size longjmp,.-longjmp
