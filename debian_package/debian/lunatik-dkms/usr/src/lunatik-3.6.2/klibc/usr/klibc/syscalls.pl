#!/usr/bin/perl
#
# Script to parse the SYSCALLS file and generate appropriate
# stubs.
#
# Pass 1: generate the C array of sizes
# Pass 2: generate the syscall stubs and other output
#

#
# Convert a string to a C array of characters,
# e.g. foo -> 'f','o','o','\0',
#
sub chararray($) {
    use bytes;

    my($s) = @_;
    my($i, $c);
    my($a) = '';

    for ($i = 0; $i < length($s); $i++) {
	$c = substr($s, $i, 1);
	if (ord($c) < 32 || ord($c) > 126) {
	    $a .= sprintf("0x%02x,", ord($c));
	} elsif ($c eq "\\" || $c eq "\'") {
	    $a .= "\'\\$c\',";
	} else {
	    $a .= "\'$c\',";
	}
    }

    return $a;
}

#
# This extracts an ASCIIZ string for the type and the additional
# information.  This is open-coded, because unpack("Z*") apparently
# is broken in Perl 5.6.1.
#
sub get_one_type($) {
    use bytes;

    my($typestr) = @_;
    my $i, $c;
    my $l = length($typestr);

    for ($i = 0; $i < $l-3; $i++) {
	$c = substr($typestr, $i, 1);
	if ($c eq "\0") {
	    return (substr($typestr, 0, $i),
		    unpack("CC", substr($typestr, $i+1, 2)),
		    substr($typestr, $i+3));
	}
    }

    return (undef, undef, undef, undef);
}

$v = $ENV{'KBUILD_VERBOSE'};
$quiet = defined($v) && ($v == 0) ? 1 : undef;

@args = ();
undef $pass;
for $arg ( @ARGV ) {
    if ( $arg =~ /^-/ ) {
	if ( $arg eq '-q' ) {
	    $quiet = 1;
	} elsif ( $arg eq '-v' ) {
	    $quiet = 0;
	} elsif ( $arg =~ /\-([0-9]+)$/ ) {
	    $pass = $1+0;
	} else {
	    die "$0: Unknown option: $arg\n";
	}
    } else {
	push(@args, $arg);
    }
}
($file, $sysstub, $arch, $bits, $unistd, $outputdir,
 $havesyscall, $typesize) = @args;

if (!$pass) {
    die "$0: Need to specify pass\n";
}

$quiet = ($pass != 2) unless defined($quiet);

require "$sysstub";

if (!open(UNISTD, "< $unistd\0")) {
    die "$0: $unistd: $!\n";
}

while ( defined($line = <UNISTD>) ) {
    chomp $line;

    if ( $line =~ /^\#\s*define\s+__NR_([A-Za-z0-9_]+)\s+(.*\S)\s*$/ ) {
	$syscalls{$1} = $2;
	print STDERR "SYSCALL FOUND: $1\n" unless ( $quiet );
    }
}
close(UNISTD);

if ($pass == 2) {
    use bytes;

    if (!open(TYPESIZE, "< $typesize\0")) {
	die "$0: $typesize: $!\n";
    }

    binmode TYPESIZE;

    $len = -s TYPESIZE;
    if (read(TYPESIZE, $typebin, $len) != $len) {
	die "$0: $typesize: short read: $!\n";
    }
    close(TYPESIZE);

    $ix = index($typebin, "\x7a\xc8\xdb\x4e\x97\xb4\x9c\x19");
    if ($ix < 0) {
	die "$0: $typesize: magic number not found\n";
    }

    # Remove magic number and bytes before it
    $typebin = substr($typebin, $ix+8);

    # Expand the types until a terminating null
    %typesize = ();
    while (1) {
	my $n, $sz, $si;
	($n, $sz, $si, $typebin) = get_one_type($typebin);
	last if (length($n) == 0);
	$typesize{$n} = $sz;
	$typesign{$n} = $si;
	print STDERR "TYPE $n: size $sz, sign $si\n" unless ($quiet);
    }
} else {
    # List here any types which should be sized even if they never occur
    # in any system calls at all.
    %type_list = ('int' => 1, 'long' => 1, 'long long' => 1,
		  'void *' => 1,
		  'intptr_t' => 1, 'uintptr_t' => 1,
		  'intmax_t' => 1, 'uintmax_t' => 1);
}

if ($pass == 2) {
    if (!open(HAVESYS, "> $havesyscall\0")) {
	die "$0: $havesyscall: $!\n";
    }

    print HAVESYS "#ifndef _KLIBC_HAVESYSCALL_H\n";
    print HAVESYS "#define _KLIBC_HAVESYSCALL_H 1\n\n";
}

if (!open(FILE, "< $file\0")) {
    die "$0: $file: $!\n";
}


if ($pass == 2) {
    print "syscall-objs := ";
}


while ( defined($line = <FILE>) ) {
    chomp $line;
    $line =~ s/\s*(|\#.*|\/\/.*)$//; # Strip comments and trailing blanks
    next unless $line;

    if ( $line =~ /^\s*(\<[^\>]+\>\s+|)([A-Za-z0-9_\*\s]+)\s+([A-Za-z0-9_,]+)(|\@[A-Za-z0-9_]+)(|\:\:[A-Za-z0-9_]+)\s*\(([^\:\)]*)\)\s*\;$/ ) {
	$archs  = $1;
	$type   = $2;
	$snames = $3;
	$stype  = $4;
	$fname  = $5;
	$argv   = $6;

	$doit  = 1;
	$maybe = 0;
	if ( $archs ne '' ) {
	    die "$file:$.: Invalid architecture spec: <$archs>\n"
		unless ( $archs =~ /^\<(|\?)(|\!)([^\>\!\?]*)\>/ );
	    $maybe = $1 ne '';
	    $not = $2 ne '';
	    $list = $3;

	    $doit = $not || ($list eq '');

	    @list = split(/,/, $list);
	    foreach  $a ( @list ) {
		if ( $a eq $arch || $a eq $bits ) {
		    $doit = !$not;
		    last;
		}
	    }
	}
	next if ( ! $doit );

	undef $sname;
	foreach $sn ( split(/,/, $snames) ) {
	    if ( defined $syscalls{$sn} ) {
		$sname = $sn;
		last;
	    }
	}
	if ( !defined($sname) ) {
	    next if ( $maybe );
	    die "$file:$.: Undefined system call: $snames\n";
	}

	$type  =~ s/\s*$//;
	$stype =~ s/^\@//;

	if ( $fname eq '' ) {
	    $fname = $sname;
	} else {
	    $fname =~ s/^\:\://;
	}

	$argv =~ s/^\s+//;
	$argv =~ s/\s+$//;

	if ($argv eq 'void') {
	    @args = ();
	} else {
	    @args = split(/\s*\,\s*/, $argv);
	}

	if ($pass == 1) {
	    # Pass 1: Add the types to the type list
	    foreach $a (@args) {
		$type_list{$a}++;
	    }
	} else {
	    # Pass 2: make sure all types defined, and actually generate stubs

	    foreach $a (@args) {
		if (!defined($typesize{$a})) {
		    die "$0: $typesize: type name missing: $a\n";
		}
	    }

	    print HAVESYS "#define _KLIBC_HAVE_SYSCALL_${fname} ${sname}\n";
	    print " \\\n\t${fname}.o";
	    make_sysstub($outputdir, $fname, $type, $sname, $stype, @args);
	}
    } else {
	die "$file:$.: Could not parse input: \"$line\"\n";
    }
}

if ($pass == 1) {
    # Pass 1: generate typesize.c
    if (!open(TYPESIZE, "> $typesize")) {
	die "$0: cannot create file: $typesize: $!\n";
    }

    print TYPESIZE "#include \"syscommon.h\"\n";

    # This compares -2 < 1 in the appropriate type, which is true for
    # signed types and false for unsigned types.  We use -2 and 1 since
    # gcc complains about comparing unsigned types with zero, and might
    # complain equally about -1 in the future.
    #
    # This test is valid (as in, doesn't cause the compiler to barf)
    # for pointers as well as for integral types; if we ever add system
    # calls which take any other kinds of types than that then this needs
    # to be smarter.
    print TYPESIZE "#define SIGNED(X) ((X)-2 < (X)1)\n";

    print TYPESIZE "\n";
    print TYPESIZE "const unsigned char type_sizes[] = {\n";
    print TYPESIZE "\t0x7a,0xc8,0xdb,0x4e,0x97,0xb4,0x9c,0x19, /* magic */\n";
    foreach $t (sort(keys(%type_list))) {
	print TYPESIZE "\t", chararray($t), "0, sizeof($t), SIGNED($t),\n";
    }
    print TYPESIZE "\t0, 0,\n";	# End sentinel
    print TYPESIZE "};\n";
    close(TYPESIZE);
} else {
    # Pass 2: finalize output files
    print "\n";

    print HAVESYS "\n#endif\n";
    close(HAVESYS);
}
