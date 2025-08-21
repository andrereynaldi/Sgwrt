package ExtUtils::MM_VOS;

use strict;
use warnings;
our $VERSION = '7.70';
$VERSION =~ tr/_//d;

require ExtUtils::MM_Unix;
our @ISA = qw(ExtUtils::MM_Unix);



sub extra_clean_files {
    return qw(*.kp);
}




1;
