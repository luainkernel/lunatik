# -*- perl -*-
#
# arch/loongarch64/sysstub.ph
#
# Script to generate system call stubs
#

# On LoongArch64, most system calls follow the standard convention, with
# the system call number in a7 and the return value in a0.

sub make_sysstub($$$$$@) {
    my($outputdir, $fname, $type, $sname, $stype, @args) = @_;

    $stype = $stype || 'common';
    open(OUT, '>', "${outputdir}/${fname}.S");
    print OUT "#include <machine/asm.h>\n";
    print OUT "#include <asm/unistd.h>\n";
    print OUT "\n";
    print OUT "ENTRY(${fname})\n";
    print OUT "\tli.w\t\$a7, __NR_${sname}\n";
    print OUT "\tb\t__syscall_${stype}\n";
    print OUT "END(${fname})\n";
    close(OUT);
}

1;
