package ExtUtils::MM_UWIN;

use strict;
use warnings;
our $VERSION = '7.70';
$VERSION =~ tr/_//d;

require ExtUtils::MM_Unix;
our @ISA = qw(ExtUtils::MM_Unix);



sub os_flavor {
    return('Unix', 'U/WIN');
}



sub replace_manpage_separator {
    my($self, $man) = @_;

    $man =~ s,/+,.,g;
    return $man;
}


1;
