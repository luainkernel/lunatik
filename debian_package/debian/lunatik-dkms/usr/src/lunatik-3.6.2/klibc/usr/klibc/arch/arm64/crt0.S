#
# arch/arm64/crt0.S
#
# void _start(void)
# {
#    __libc_init(elf_structure, atexit_ptr);
# }
#

	.text
	.balign 8
	.type _start,#function
	.globl _start

_start:
	mov	x0, sp
	mov	x1, #0
	bl	__libc_init
	.size _start,.-_start
