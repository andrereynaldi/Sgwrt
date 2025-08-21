package ExtUtils::MM_QNX;

use strict;
use warnings;
our $VERSION = '7.70';
$VERSION =~ tr/_//d;

require ExtUtils::MM_Unix;
our @ISA = qw(ExtUtils::MM_Unix);



sub extra_clean_files {
    my $self = shift;

    my @errfiles = @{$self->{C}};
    for ( @errfiles ) {
	s/.c$/.err/;
    }

    return( @errfiles, 'perlmain.err' );
}




1;
