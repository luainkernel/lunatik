#!/usr/bin/perl

$v = $ENV{'KBUILD_VERBOSE'};
$quiet = defined($v) ? !$v : 0;

@args = ();
for $arg ( @ARGV ) {
    if ( $arg =~ /^-/ ) {
	if ( $arg eq '-q' ) {
	    $quiet = 1;
	} else {
	    die "$0: Unknown option: $arg\n";
	}
    } else {
	push(@args, $arg);
    }
}
($file, $arch, $outputdir) = @args;

if (!open(FILE, "< $file")) {
    die "$file: $!\n";
}

print "socketcall-objs := ";
while ( defined($line = <FILE>) ) {
    chomp $line;
    $line =~ s/\s*(|\#.*|\/\/.*)$//;	# Strip comments and trailing blanks
    next unless $line;

    if ( $line =~ /^\s*\<\?\>\s*(.*)\s+([_a-zA-Z][_a-zA-Z0-9]+)\s*\((.*)\)\s*\;$/ ) {
	$type = $1;
	$name = $2;
	$argv = $3;

	@args = split(/\s*\,\s*/, $argv);
	@cargs = ();

	$i = 0;
	for $arg ( @args ) {
	    push(@cargs, "$arg a".$i++);
	}
	$nargs = $i;
	print " \\\n\t${name}.o";

	open(OUT, "> ${outputdir}/${name}.c")
	    or die "$0: Cannot open ${outputdir}/${name}.c\n";

	print OUT "#include \"socketcommon.h\"\n";
	print OUT "\n";
	print OUT "#if _KLIBC_SYS_SOCKETCALL\n";
	print OUT "# define DO_THIS_SOCKETCALL\n";
	print OUT "#else\n";
	print OUT "# if !defined(__NR_${name})";
	if ($name eq 'accept') {
	    print OUT " && !defined(__NR_accept4)";
	}
	print OUT "\n#  define DO_THIS_SOCKETCALL\n";
	print OUT "# endif\n";
	print OUT "#endif\n\n";

	print OUT "#if defined(DO_THIS_SOCKETCALL) && defined(SYS_\U${name}\E)\n\n";

	print OUT "extern long __socketcall(int, const unsigned long *);\n\n";

	print OUT "$type ${name}(", join(', ', @cargs), ")\n";
	print OUT "{\n";
	print OUT "    unsigned long args[$nargs];\n";
	for ( $i = 0 ; $i < $nargs ; $i++ ) {
	    print OUT "    args[$i] = (unsigned long)a$i;\n";
	}
	print OUT "    return ($type) __socketcall(SYS_\U${name}\E, args);\n";
	print OUT "}\n\n";

	print OUT "#endif\n";

	close(OUT);
    } else {
	die "$file:$.: Could not parse input\n";
    }
}

print "\n";
