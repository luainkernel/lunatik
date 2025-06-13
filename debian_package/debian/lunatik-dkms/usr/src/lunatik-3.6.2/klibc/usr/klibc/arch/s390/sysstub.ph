# -*- perl -*-
#
# arch/s390/sysstub.ph
#
# Script to generate system call stubs
#

sub make_sysstub($$$$$@) {
    my($outputdir, $fname, $type, $sname, $stype, @args) = @_;
    my($t);
    my($r, $llregs) = (0, ($typesize{'void *'} == 8) ? 1 : 2);

    foreach $t (@args) {
	    $r += ($typesize{$t} == 8) ? $llregs : 1;
    }

    open(OUT, '>', "${outputdir}/${fname}.S");
    print OUT <<EOF;
#include <asm/unistd.h>

	.type ${fname},\@function
	.globl ${fname}
${fname}:
.if ${r} > 6
.print "System call with more than six parameters not supported yet."
.err
.endif
.if ${r} == 6
#ifndef __s390x__
	st	%r7,56(%r15)
	l	%r7,96(%r15)
#else
	stg	%r7,80(%r15)
	lg	%r7,160(%r15)
#endif
.endif
.if __NR_${sname} < 256
	svc	__NR_${sname}
.else
	la	%r1,__NR_${sname}
	svc	0
.endif
.if ${r} == 6
#ifndef __s390x__
	l	%r7,56(%r15)
#else
	lg	%r7,160(%r15)
#endif
.endif
#ifndef __s390x__
	bras	%r3,1f
	.long	__syscall_common
1:	l	%r3,0(%r3)
	br	%r3
#else
	brasl	%r3,__syscall_common
#endif
	.size	${fname},.-${fname}
EOF
    close(OUT);
}

1;
