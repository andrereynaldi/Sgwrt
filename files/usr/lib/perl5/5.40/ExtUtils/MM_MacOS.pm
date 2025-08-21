package ExtUtils::MM_MacOS;

use strict;
use warnings;

our $VERSION = '7.70';
$VERSION =~ tr/_//d;

sub new {
    die 'MacOS Classic (MacPerl) is no longer supported by MakeMaker';
}


1;
