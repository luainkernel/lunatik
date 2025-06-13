# -*- perl -*-
#
# arch/i386/sysstub.ph
#
# Script to generate system call stubs
#

sub make_sysstub($$$$$@) {
    my($outputdir, $fname, $type, $sname, $stype, @args) = @_;

    open(OUT, '>', "${outputdir}/${fname}.S");
    print OUT "#include <asm/unistd.h>\n";
    print OUT "\n";
    print OUT "\t.type ${fname},\@function\n";
    print OUT "\t.globl ${fname}\n";
    print OUT "${fname}:\n";

    $stype = 'common' if ( $stype eq '' );

    print OUT "\tpushl \$__NR_${sname}\n";
    print OUT "\tjmp __syscall_$stype\n";
    print OUT "\t.size ${fname},.-${fname}\n";
    close(OUT);
}

1;
