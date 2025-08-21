package Encode::Unicode;

use strict;
use warnings;

our $VERSION = do { my @r = ( q$Revision: 2.20 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r };

use XSLoader;
XSLoader::load( __PACKAGE__, $VERSION );


use Encode ();

our %BOM_Unknown = map { $_ => 1 } qw(UTF-16 UTF-32);

for my $name (
    qw(UTF-16 UTF-16BE UTF-16LE
    UTF-32 UTF-32BE UTF-32LE
    UCS-2BE  UCS-2LE)
  )
{
    my ( $size, $endian, $ucs2, $mask );
    $name =~ /^(\w+)-(\d+)(\w*)$/o;
    if ( $ucs2 = ( $1 eq 'UCS' ) ) {
        $size = 2;
    }
    else {
        $size = $2 / 8;
    }
    $endian = ( $3 eq 'BE' ) ? 'n' : ( $3 eq 'LE' ) ? 'v' : '';
    $size == 4 and $endian = uc($endian);

    my $obj = bless {
        Name   => $name,
        size   => $size,
        endian => $endian,
        ucs2   => $ucs2,
    } => __PACKAGE__;
    Encode::define_encoding($obj, $name);
}

use parent qw(Encode::Encoding);

sub renew {
    my $self = shift;
    $BOM_Unknown{ $self->name } or return $self;
    my $clone = bless {%$self} => ref($self);
    $clone->{renewed}++;    # so the caller knows it is renewed.
    return $clone;
}

1;
__END__


