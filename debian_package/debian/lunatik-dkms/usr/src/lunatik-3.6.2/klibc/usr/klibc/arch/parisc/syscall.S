/*
 * arch/parisc/syscall.S
 *
 * %r20 contains the system call number, %r2 contains whence we came
 *
 */

	.text
	.align 64				; cache-width aligned
	.globl	__syscall_common
	.type	__syscall_common,@function
__syscall_common:
	ldo 		0x40(%sp),%sp
	stw 		%rp,-0x54(%sp)		; save return pointer

	ldw 		-0x74(%sp),%r22		; %arg4
	ldw 		-0x78(%sp),%r21		; %arg5

	ble		0x100(%sr2, %r0)	; jump to gateway page
	nop					; can we move a load here?

	ldi		-0x1000,%r19		; %r19 = -4096
	sub		%r0,%ret0,%r22		; %r22 = -%ret0
	cmpb,>>=,n	%r19,%ret0,1f		; if %ret0 >= -4096UL
	ldi		-1,%ret0		; nullified on taken forward

	/* store %r22 to errno... */
	ldil		L%errno,%r1
	ldo		R%errno(%r1),%r1
	stw		%r22,0(%r1)
1:
	ldw 		-0x54(%sp),%rp		; restore return pointer
	bv		%r0(%rp)		; jump back
	ldo 		-0x40(%sp),%sp

	.size __syscall_common,.-__syscall_common
