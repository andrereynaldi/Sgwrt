package IPC::Open2;

use strict;

require 5.006;
use Exporter 'import';

our $VERSION	= 1.06;
our @EXPORT		= qw(open2);



require IPC::Open3;

sub open2 {
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;
    return IPC::Open3::_open3('open2', $_[1], $_[0], '>&STDERR', @_[2 .. $#_]);
}

1
