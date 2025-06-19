# -*- perl -*-
#
# arch/ppc64/sysstub.ph
#
# Script to generate system call stubs
#

sub make_sysstub($$$$$@) {
    my($outputdir, $fname, $type, $sname, $stype, @args) = @_;

    open(OUT, '>', "${outputdir}/${fname}.S");
    print OUT <<EOF;
#include <asm/unistd.h>

	.text
	.balign 4
	.globl	${fname}
#if _CALL_ELF == 2
	.type ${fname},\@function
${fname}:
0:	addis	2,12,(.TOC.-0b)\@ha
	addi	2,2,(.TOC.-0b)\@l
	.localentry ${fname},.-${fname}
#else
	.section ".opd","aw"
	.balign 8
${fname}:
	.quad	.${fname}, .TOC.\@tocbase, 0
	.previous
	.type	.${fname},\@function
	.globl	.${fname}
.${fname}:
#endif
	li	0, __NR_${sname}
	sc
	bnslr
	b	__syscall_error
#if _CALL_ELF == 2
	.size ${fname},.-${fname}
#else
	.size ${fname},.-.${fname}
#endif
EOF
    close(OUT);
}

1;
