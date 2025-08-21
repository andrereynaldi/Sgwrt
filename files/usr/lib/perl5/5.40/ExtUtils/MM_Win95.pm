package ExtUtils::MM_Win95;

use strict;
use warnings;

our $VERSION = '7.70';
$VERSION =~ tr/_//d;

require ExtUtils::MM_Win32;
our @ISA = qw(ExtUtils::MM_Win32);

use ExtUtils::MakeMaker::Config;



sub max_exec_len {
    my $self = shift;

    return $self->{_MAX_EXEC_LEN} ||= 1024;
}



sub os_flavor {
    my $self = shift;
    return ($self->SUPER::os_flavor, 'Win9x');
}




1;
