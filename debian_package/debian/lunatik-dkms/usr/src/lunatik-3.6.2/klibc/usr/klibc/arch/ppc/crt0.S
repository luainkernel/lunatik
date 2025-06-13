#
# arch/ppc/crt0.S
#

	.text
	.align 4
	.type _start,@function
	.globl _start
_start:
	stwu	1,-16(1)
	addi	3,1,16
	/*
	 * the SVR4abippc.pdf specifies r7 as a pointer to
	 * a termination function point
	 * However, Section 8.4.1 of the LSB API docs say that
	 * The value to be placed into register r7, the termination
	 * function pointer, is not passed to the process.
	 * So we stub it out, instead.
	 */
	li	4,0
	bl	__libc_init

	.size _start,.-_start
