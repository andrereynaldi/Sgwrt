
package Scalar::Util;

use strict;
use warnings;
require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
  blessed refaddr reftype weaken unweaken isweak

  dualvar isdual isvstring looks_like_number openhandle readonly set_prototype
  tainted
);
our $VERSION    = "1.63";
$VERSION =~ tr/_//d;

require List::Util; # List::Util loads the XS
List::Util->VERSION( $VERSION ); # Ensure we got the right XS version (RT#100863)

sub export_fail {
  if (grep { /^isvstring$/ } @_ ) {
    require Carp;
    Carp::croak("Vstrings are not implemented in this version of perl");
  }

  @_;
}

sub set_prototype(&$)
{
  my ( $code, $proto ) = @_;
  return Sub::Util::set_prototype( $proto, $code );
}

1;

__END__


