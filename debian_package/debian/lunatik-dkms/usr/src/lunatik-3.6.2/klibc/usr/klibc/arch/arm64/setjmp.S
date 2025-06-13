#
# arch/arm64/setjmp.S
#
# setjmp/longjmp for arm64
#

# we specify -mgeneral-regs-only as a build flag thus do not need to
# save d8-d15

	.text
	.balign 8
	.globl setjmp
	.type setjmp, #function
setjmp:
	mov	x1, sp
	stp	x18, x19, [x0, #0]
	stp	x20, x21, [x0, #16]
	stp	x22, x23, [x0, #32]
	stp	x24, x25, [x0, #48]
	stp	x26, x27, [x0, #64]
	stp	x28, x29, [x0, #80]
	stp	x30, x1,  [x0, #96]
	mov	x0, #0 			/* set the return value of setjmp */
	br	x30
	.size setjmp,.-setjmp

	.text
	.balign 8
	.globl longjmp
	.type longjmp, #function
longjmp:
	ldp	x18, x19, [x0, #0]
	ldp	x20, x21, [x0, #16]
	ldp	x22, x23, [x0, #32]
	ldp	x24, x25, [x0, #48]
	ldp	x26, x27, [x0, #64]
	ldp	x28, x29, [x0, #80]
	ldp	x30, x2,  [x0, #96]
	mov	sp, x2
	mov	x0, x1
	cbnz	x1, 1f
	mov	x0, #1
1:
	br	x30
	.size longjmp,.-longjmp
