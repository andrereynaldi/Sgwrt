package ExtUtils::MY;

use strict;
require ExtUtils::MM;

our $VERSION = '7.70';
$VERSION =~ tr/_//d;
our @ISA = qw(ExtUtils::MM);

{
    package MY;
    our @ISA = qw(ExtUtils::MY);
}

sub DESTROY {}


