package ExtUtils::MakeMaker::Config;

use strict;
use warnings;

our $VERSION = '7.70';
$VERSION =~ tr/_//d;

use Config ();

our %Config = %Config::Config;

sub import {
    my $caller = caller;

    no strict 'refs';   ## no critic
    *{$caller.'::Config'} = \%Config;
}

1;


