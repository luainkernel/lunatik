#!/usr/bin/perl
#
# Generate dependencies for *generated* header files.  Generated
# header files have to use #include "foo.h" syntax.
#

($src, $obj, @build_headers) = @ARGV;
%build_headers = map { $_ => 1 } @build_headers;

open(GENDEPS, "> $obj/.gendeps\0")
    or die "$0: Cannot create $obj/.gendeps: $!\n";

opendir(DIR, $src) or die "$0: Cannot opendir $src: $!\n";
while ( defined($file = readdir(DIR)) ) {
    if ( $file =~ /^(.*)\.c$/ ) {
	$basename = $1;
	@hdrs = ();
	open(FILE, "< $src/$file\0")
	    or die "$0: Cannot open $src/$file: $!\n";
	while ( defined($line = <FILE>) ) {
	    if ( $line =~ /^\s*\#\s*include\s+\"(.*)\"/ ) {
		$header = $1;

		if ( $build_headers{$header} ) {
		    push(@hdrs, "\$(obj)/$header");
		}
	    }
	}
	close(FILE);

	if (scalar(@hdrs)) {
	    print GENDEPS "\$(obj)/$basename.o: ", join(' ', @hdrs), "\n";
	}
    }
}

closedir(DIR);
close(GENDEPS);
