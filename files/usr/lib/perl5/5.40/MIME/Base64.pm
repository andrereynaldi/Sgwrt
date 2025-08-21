package MIME::Base64;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(encode_base64 decode_base64);
our @EXPORT_OK = qw(encode_base64url decode_base64url encoded_base64_length decoded_base64_length);

our $VERSION = '3.16_01';

require XSLoader;
XSLoader::load('MIME::Base64', $VERSION);

*encode = \&encode_base64;
*decode = \&decode_base64;

sub encode_base64url {
    my $e = encode_base64(shift, "");
    $e =~ s/=+\z//;
    $e =~ tr[+/][-_];
    return $e;
}

sub decode_base64url {
    my $s = shift;
    $s =~ tr[-_][+/];
    $s .= '=' while length($s) % 4;
    return decode_base64($s);
}

1;

__END__

