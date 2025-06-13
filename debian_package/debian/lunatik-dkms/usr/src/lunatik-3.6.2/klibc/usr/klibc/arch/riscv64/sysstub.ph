# -*- perl -*-
#
# arch/riscv/sysstub.ph
#
# Script to generate system call stubs
#

# On RISC-V, most system calls follow the standard convention, with the
# system call number in x17 (a7) and the return value in x10 (a0).

sub make_sysstub($$$$$@) {
    my($outputdir, $fname, $type, $sname, $stype, @args) = @_;

    $stype = $stype || 'common';
    open(OUT, '>', "${outputdir}/${fname}.S");
    print OUT "#include <machine/asm.h>\n";
    print OUT "#include <asm/unistd.h>\n";
    print OUT "\n";
    print OUT "ENTRY(${fname})\n";
    print OUT "\tli\ta7, __NR_${sname}\n";
    print OUT "\tj\t__syscall_${stype}\n";
    print OUT "END(${fname})\n";
    close(OUT);
}

1;
