package MIME::QuotedPrint;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(encode_qp decode_qp);

our $VERSION = '3.16_01';

use MIME::Base64;  # will load XS version of {en,de}code_qp()

*encode = \&encode_qp;
*decode = \&decode_qp;

1;

__END__

