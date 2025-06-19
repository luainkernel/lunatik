	.global .umul
	.section	".text"
	.align 4
	.global __muldi3
	.type	__muldi3, #function
	.proc	017
__muldi3:
	save	%sp, -104, %sp
	mov	%i1, %o0
	call	.umul, 0
	 mov	%i3, %o1
	mov	%o0, %l2
	mov	%o1, %l3
	mov	%i1, %o0
	call	.umul, 0
	 mov	%i2, %o1
	mov	%i0, %o1
	mov	%o0, %l0
	call	.umul, 0
	 mov	%i3, %o0
	mov	0, %l1
	add	%l0, %o0, %l0
	addcc	%l3, %l1, %i1
	addx	%l2, %l0, %i0
	jmp	%i7+8
	 restore
	.size	__muldi3, .-__muldi3
