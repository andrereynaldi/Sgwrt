package ExtUtils::MM_DOS;

use strict;
use warnings;

our $VERSION = '7.70';
$VERSION =~ tr/_//d;

require ExtUtils::MM_Any;
require ExtUtils::MM_Unix;
our @ISA = qw( ExtUtils::MM_Any ExtUtils::MM_Unix );



sub os_flavor {
    return('DOS');
}


sub replace_manpage_separator {
    my($self, $man) = @_;

    $man =~ s,/+,__,g;
    return $man;
}


sub xs_static_lib_is_xs {
    return 1;
}


1;
