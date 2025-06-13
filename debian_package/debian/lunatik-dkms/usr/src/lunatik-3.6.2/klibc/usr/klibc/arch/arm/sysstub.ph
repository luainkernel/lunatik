# -*- perl -*-
#
# arch/arm/sysstub.ph
#
# Script to generate system call stubs
#


sub make_sysstub($$$$$@) {
    my($outputdir, $fname, $type, $sname, $stype, @args) = @_;

    open(OUT, '>', "${outputdir}/${fname}.S");
    print  OUT "#include <asm/unistd.h>\n";
    print  OUT "#include <klibc/asmmacros.h>\n";

    print  OUT "	.text\n";
    print  OUT "	.type	${fname}, #function\n";
    print  OUT "	.globl	${fname}\n";

    print  OUT "#ifndef __thumb__\n";

    print  OUT "#ifndef __ARM_EABI__\n";

    # ARM version first
    print  OUT "	.balign	4\n";
    print  OUT "${fname}:\n";
    print  OUT "	stmfd	sp!,{r4,r5,lr}\n";
    print  OUT "	ldr	r4,[sp,#12]\n";
    print  OUT "	ldr	r5,[sp,#16]\n";
    print  OUT "	swi	# __NR_${sname}\n";
    print  OUT "	b	__syscall_common\n";

    print  OUT "#else /* __ARM_EABI__ */\n";

    # ARM EABI version
    print  out "	.balign	4\n";
    print  OUT "${fname}:\n";
    print  OUT "	stmfd	sp!,{r4,r5,r7,lr}\n";
    print  OUT "	bl	__syscall_common\n";
    print  OUT "	.word	__NR_${sname}\n";

    print  OUT "#endif /* __ARM_EABI__ */\n";
    print  OUT "#else /* __thumb__ */\n";

    # Thumb version
    print  OUT "	.balign	8\n";
    print  OUT "	.thumb_func\n";
    print  OUT "${fname}:\n";
    print  OUT "	push	{r4,r5,r7,lr}\n";
    print  OUT "	bl	__syscall_common\n";
    print  OUT "	.short	__NR_${sname}\n";

    print  OUT "#endif /* __thumb__*/\n";

    print  OUT "	.size	${fname},.-${fname}\n";
}

1;
