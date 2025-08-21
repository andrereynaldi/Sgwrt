package ExtUtils::Liblist;

use strict;
use warnings;

our $VERSION = '7.70';
$VERSION =~ tr/_//d;

use File::Spec;
require ExtUtils::Liblist::Kid;
our @ISA = qw(ExtUtils::Liblist::Kid File::Spec);

sub ext {
    goto &ExtUtils::Liblist::Kid::ext;
}

sub lsdir {
  shift;
  my $rex = qr/$_[1]/;
  opendir my $dir_fh, $_[0];
  my @out = grep /$rex/, readdir $dir_fh;
  closedir $dir_fh;
  return @out;
}

__END__


