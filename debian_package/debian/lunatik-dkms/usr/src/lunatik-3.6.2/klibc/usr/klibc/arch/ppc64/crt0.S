#
# arch/ppc64/crt0.S
#
# void _start(void)
# {
#    /* Divine up argc, argv, and envp */
#    environ = envp;
#    exit(main(argc, argv, envp));
# }
#

	.text
	.balign 4
	.globl	_start
#if _CALL_ELF == 2
	.type _start,@function
_start:
#else
	.section ".opd","aw"
	.balign 8
_start:
	.quad	._start, .TOC.@tocbase, 0
	.previous
	.type	._start,@function
._start:
#endif

#if _CALL_ELF == 2
0:	addis	2,12,.TOC.-0b@ha
	addi	2,2,.TOC.-0b@l
#endif

	stdu	%r1,-32(%r1)
	addi	%r3,%r1,32
	li	%r4,0		/* fini (unused) */
	b	__libc_init
	nop

#if _CALL_ELF == 2
	.size _start,.-_start
#else
	.size _start,.-._start
#endif
