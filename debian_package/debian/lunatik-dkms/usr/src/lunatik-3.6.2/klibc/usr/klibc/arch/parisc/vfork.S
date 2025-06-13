/*
 * arch/parisc/vfork.S, "vfork() me harder. ugh." -- kyle
 *
 * %rp contains whence we came,
 * %rp is saved and restored across the syscall, thankfully.
 *
 */

	.text
	.align 64				; cache-width aligned
	.globl	vfork
	.type	vfork,@function
vfork:
	/* pid_t vfork(void) */
	ldi		113,%r20
	ble		0x100(%sr2, %r0)	; jump to gateway page
	nop

	ldi		-0x1000,%r19		; %r19 = -4096
	sub		%r0,%ret0,%r22		; %r22 = -%ret0
	cmpb,>>=,n	%r19,%ret0,1f		; if %ret0 >= -4096UL
	ldi		-1,%ret0		; nullified on taken forward

	/* store %r22 to errno... */
	ldil		L%errno,%r1
	ldo		R%errno(%r1),%r1
	stw		%r22,0(%r1)
1:
	bv		%r0(%rp)		; jump back
	nop

	.size vfork,.-vfork
